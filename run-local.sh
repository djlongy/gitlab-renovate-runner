#!/usr/bin/env bash
# Run Renovate inside RENOVATE_IMAGE with podman or docker, the same way the
# pipeline does. The pipeline calls it on a shell executor; from a workstation or
# a shell runner host, put the settings in .env (copy .env.example) and run:
#
#   ./run-local.sh --dry-run        extract and look up, open nothing
#   ./run-local.sh                  real run: opens merge requests
#   ./run-local.sh --validate       check config.js and the presets only
#
# .env is read automatically (ENV_FILE=path to use another file), so the token
# never goes on a command line or into shell history.
set -euo pipefail
cd "$(dirname "$0")"

case "${1:-}" in
  ''|--dry-run|--validate) ;;
  *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac

env_file=${ENV_FILE:-.env}
if [ -f "$env_file" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$env_file"
  set +a
  echo "read settings from $env_file"
fi

# In CI these default to this GitLab and this project.
export RENOVATE_ENDPOINT=${RENOVATE_ENDPOINT:-${CI_API_V4_URL:-}}
export RENOVATE_PRESET_REPO=${RENOVATE_PRESET_REPO:-${CI_PROJECT_PATH:-}}
missing=
for name in RENOVATE_TOKEN RENOVATE_ENDPOINT RENOVATE_PRESET_REPO; do
  [ -n "${!name:-}" ] || missing="$missing $name"
done
if [ -n "$missing" ] && [ "${1:-}" != "--validate" ]; then
  echo "ERROR: not set:$missing. Copy .env.example to .env and fill it in." >&2
  exit 1
fi

engine=$(command -v podman || command -v docker || true)
[ -n "$engine" ] || { echo "ERROR: need podman or docker" >&2; exit 1; }
image=${RENOVATE_IMAGE:-}
[ -n "$image" ] || image=$(sed -n 's/^  RENOVATE_IMAGE: //p' .gitlab-ci.yml)

# Pulling the image: log in with the credentials Renovate uses for lookups on that
# host: REGISTRY_USERNAME / _PASSWORD when REGISTRY_HOST is the image's host, else
# the DOCKER_<HOST>_USERNAME / _PASSWORD pair (host upper-cased, . - : as _).
# Without either, an earlier `podman login` or a public image is used.
registry=${image%%/*}
case "$registry" in
  *.*|*:*|localhost)
    key=$(printf '%s' "$registry" | tr '.:-' '___' | tr '[:lower:]' '[:upper:]')
    user_var="DOCKER_${key}_USERNAME" pass_var="DOCKER_${key}_PASSWORD"
    registry_host=${REGISTRY_HOST:-}
    registry_host=${registry_host#https://}; registry_host=${registry_host#http://}; registry_host=${registry_host%/}
    if [ "$registry_host" = "$registry" ]; then
      user_var=REGISTRY_USERNAME pass_var=REGISTRY_PASSWORD
    fi
    if [ -n "${!user_var:-}" ] && [ -n "${!pass_var:-}" ]; then
      printf '%s' "${!pass_var}" | "$engine" login --username "${!user_var}" --password-stdin "$registry" >/dev/null \
        || { echo "ERROR: $engine login to $registry as ${!user_var} failed ($user_var / $pass_var)" >&2; exit 1; }
      echo "logged in to $registry as ${!user_var} ($user_var)"
    else
      echo "image $image: no $user_var / $pass_var set, pulling with any existing $(basename "$engine") login"
    fi
    ;;
esac

if [ "${1:-}" = "--validate" ]; then
  exec "$engine" run --rm -v "$PWD:/work:ro,Z" -w /work --entrypoint renovate-config-validator \
    "$image" config.js default.json helm.json
fi

args=(run --rm -v "$PWD/config.js:/usr/src/app/config.js:ro,Z" -e RENOVATE_CONFIG_FILE=/usr/src/app/config.js)
if [ "${1:-}" = "--dry-run" ]; then
  args+=(-e RENOVATE_DRY_RUN=full)
fi
# The package cache lives in RENOVATE_BASE_DIR (CI: the job cache), mounted at
# the same path so the passed-through variable is valid inside the container.
if [ -n "${RENOVATE_BASE_DIR:-}" ]; then
  mkdir -p "$RENOVATE_BASE_DIR"
  args+=(-v "$RENOVATE_BASE_DIR:$RENOVATE_BASE_DIR:Z")
fi
# Rootless podman: the image's user (12021, group 0) becomes the calling user
# on the host, so it can write the mounted cache and the runner can clean it.
case "$engine" in
  */podman) args+=("--userns=keep-id:uid=12021,gid=0") ;;
esac
if [ -n "${CONTAINER_ARGS:-}" ]; then
  read -r -a extra <<< "$CONTAINER_ARGS"
  args+=("${extra[@]}")
fi
# An internal CA is appended to the image's public roots inside the container:
# SSL_CERT_FILE and GIT_SSL_CAINFO replace the trust store rather than add to it.
# Renovate's lookups read NODE_EXTRA_CA_CERTS, git reads GIT_SSL_CAINFO, and
# helm, go and pip read SSL_CERT_FILE. Renovate passes only these to its tools.
# The mount is a private copy: SELinux refuses to relabel a system file such as
# /etc/pki/tls/certs/ca-bundle.crt, and unlabelled the container cannot read it.
command=(renovate)
if [ -n "${CA_BUNDLE:-}" ]; then
  [ -r "$CA_BUNDLE" ] || { echo "ERROR: CA_BUNDLE=$CA_BUNDLE is not a readable file" >&2; exit 1; }
  ca_dir=$(mktemp -d)
  trap 'rm -rf "$ca_dir"' EXIT
  cp "$CA_BUNDLE" "$ca_dir/internal-ca.crt"
  args+=(-v "$ca_dir/internal-ca.crt:/internal-ca.crt:ro,Z" -e NODE_EXTRA_CA_CERTS=/internal-ca.crt
         -e SSL_CERT_FILE=/tmp/ca-bundle.crt -e GIT_SSL_CAINFO=/tmp/ca-bundle.crt
         --entrypoint /bin/sh)
  command=(-c 'cat /etc/ssl/certs/ca-certificates.crt /internal-ca.crt > /tmp/ca-bundle.crt && exec renovate')
fi
# Pass through every RENOVATE_* variable, the proxy settings, REGISTRY_* and the
# <TYPE>_<HOST>_USERNAME / _PASSWORD registry credentials by name only.
while IFS='=' read -r name _; do
  case "$name" in
    RENOVATE_CONFIG_FILE|RENOVATE_IMAGE) ;;
    RENOVATE_*|LOG_LEVEL|HTTP_PROXY|HTTPS_PROXY|NO_PROXY|http_proxy|https_proxy|no_proxy) args+=(-e "$name") ;;
    REGISTRY_HOST|REGISTRY_USERNAME|REGISTRY_PASSWORD) args+=(-e "$name") ;;
    DOCKER_*_USERNAME|DOCKER_*_PASSWORD|HELM_*_USERNAME|HELM_*_PASSWORD|PYPI_*_USERNAME|PYPI_*_PASSWORD) args+=(-e "$name") ;;
  esac
done < <(env)
"$engine" "${args[@]}" "$image" "${command[@]}"
