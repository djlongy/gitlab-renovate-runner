#!/usr/bin/env bash
# Run Renovate from a workstation with podman or docker, the same way the
# pipeline does. For a site whose runners cannot reach the proxy but a desktop
# can.
#
#   export RENOVATE_TOKEN=...                 bot user's token
#   export RENOVATE_ENDPOINT=https://gitlab.example.com/api/v4
#   export RENOVATE_PRESET_REPO=platform/renovate-runner
#   export RENOVATE_AUTODISCOVER_FILTER='platform/**'   (optional)
#   export HTTPS_PROXY=http://proxy.example.com:3128    (optional)
#   export NO_PROXY=gitlab.example.com                  (the GitLab host)
#   export CA_BUNDLE=/etc/pki/tls/certs/ca-bundle.crt   (optional)
#   export CONTAINER_ARGS='--network host'              (optional, extra run flags)
#   ./run-local.sh                  real run
#   ./run-local.sh --dry-run        extract and look up, open nothing
set -euo pipefail
cd "$(dirname "$0")"

engine=$(command -v podman || command -v docker || true)
[ -n "$engine" ] || { echo "ERROR: need podman or docker" >&2; exit 1; }
: "${RENOVATE_TOKEN:?set RENOVATE_TOKEN}"
: "${RENOVATE_ENDPOINT:?set RENOVATE_ENDPOINT, e.g. https://gitlab.example.com/api/v4}"
: "${RENOVATE_PRESET_REPO:?set RENOVATE_PRESET_REPO to the path of this project}"
image=${RENOVATE_IMAGE:-}
[ -n "$image" ] || image=$(sed -n 's/^  RENOVATE_IMAGE: //p' .gitlab-ci.yml)

args=(run --rm -v "$PWD/config.js:/usr/src/app/config.js:ro,Z" -e RENOVATE_CONFIG_FILE=/usr/src/app/config.js)
if [ "${1:-}" = "--dry-run" ]; then
  args+=(-e RENOVATE_DRY_RUN=full)
fi
if [ -n "${CONTAINER_ARGS:-}" ]; then
  read -r -a extra <<< "$CONTAINER_ARGS"
  args+=("${extra[@]}")
fi
# An internal CA is appended to the image's public roots inside the container:
# SSL_CERT_FILE and GIT_SSL_CAINFO replace the trust store rather than add to it.
command=(renovate)
if [ -n "${CA_BUNDLE:-}" ]; then
  args+=(-v "$CA_BUNDLE:/internal-ca.crt:ro,Z" -e NODE_EXTRA_CA_CERTS=/internal-ca.crt
         -e SSL_CERT_FILE=/tmp/ca-bundle.crt -e GIT_SSL_CAINFO=/tmp/ca-bundle.crt
         -e REQUESTS_CA_BUNDLE=/tmp/ca-bundle.crt --entrypoint /bin/sh)
  command=(-c 'cat /etc/ssl/certs/ca-certificates.crt /internal-ca.crt > /tmp/ca-bundle.crt && exec renovate')
fi
# Pass through every RENOVATE_* variable, the proxy settings, and the
# <TYPE>_<HOST>_USERNAME / _PASSWORD registry credentials by name only.
while IFS='=' read -r name _; do
  case "$name" in
    RENOVATE_CONFIG_FILE|RENOVATE_IMAGE) ;;
    RENOVATE_*|LOG_LEVEL|HTTP_PROXY|HTTPS_PROXY|NO_PROXY|http_proxy|https_proxy|no_proxy) args+=(-e "$name") ;;
    DOCKER_*_USERNAME|DOCKER_*_PASSWORD|HELM_*_USERNAME|HELM_*_PASSWORD|PYPI_*_USERNAME|PYPI_*_PASSWORD) args+=(-e "$name") ;;
  esac
done < <(env)
exec "$engine" "${args[@]}" "$image" "${command[@]}"
