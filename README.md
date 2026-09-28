# gitlab-renovate-runner

Runs Renovate on a schedule against your GitLab projects, with shared presets for Helm deployment repositories.

## Requirements

- A GitLab group access token on the group to update: role Developer, scopes `api` and
  `write_repository`. Its name becomes the bot user's display name on every merge
  request. The bot must also read this project, so keep it in the same group.
- A runner that reaches GitLab and the upstream registries, directly or through an HTTP
  proxy. Docker and kubernetes executors run the jobs in `RENOVATE_IMAGE`. A shell
  executor needs rootless podman or docker for the runner user, and runs the same image
  through `run-local.sh`. With rootless podman the `-full` image (about 8 GB unpacked)
  lives in that user's home, under `~/.local/share/containers`.

## CI/CD variables

Set on this project. `.env.example` carries the same names for `run-local.sh`, which
reads `.env` itself. Renovate reads any other `RENOVATE_*` option from the environment.

| Req | Name | Default | Purpose |
|---|---|---|---|
| Required | `RENOVATE_TOKEN` | none | The group access token above. Masked |
| When local | `RENOVATE_ENDPOINT`, `RENOVATE_PRESET_REPO` | this GitLab, this project | API URL and this project's path. CI sets both |
| Optional | `RENOVATE_AUTODISCOVER_FILTER` | every project the bot sees | Scope, e.g. `platform/**` |
| Optional | `RENOVATE_AUTODISCOVER`, `RENOVATE_REPOSITORIES` | `true`, none | `false` plus a comma list runs those projects only |
| When internal CA | `CA_BUNDLE` | image roots | File variable: PEM bundle added to the image's public roots |
| When internal hosts | `RENOVATE_INTERNAL_HOSTS` | GitLab only | Comma list of other hosts on private addresses Renovate may call |
| Optional | `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` | none | Proxy for lookups. Put GitLab and internal hosts in `NO_PROXY` |
| Optional | `RENOVATE_REGISTRY_ALIASES_JSON` | `{}` | Mirror prefix to upstream, e.g. `{"registry.example.com/dockerhub":"docker.io"}` |
| When private registry | `DOCKER_<HOST>_USERNAME`, `DOCKER_<HOST>_PASSWORD` | none | Host upper-cased with `.` `-` `:` as `_`. `HELM_` and `PYPI_` work the same. See [Registry credentials](#registry-credentials) |
| Optional | `RENOVATE_IMAGE` | `docker.io/renovate/renovate:<pinned>-full` | Job image. Point it at your registry |
| Optional | `RENOVATE_DRY_RUN`, `LOG_LEVEL` | unset, `info` | `full` opens nothing. `debug` lists every dependency |

## Usage

A project opts in with a `renovate.json` on its default branch. Copy
`examples/renovate.json` and change `platform/renovate-runner` to this project's path:

```json
{
  "extends": ["local>platform/renovate-runner", "local>platform/renovate-runner:helm"]
}
```

## Minimum configuration

**Settings > CI/CD > Variables**: `RENOVATE_TOKEN` (masked), plus `CA_BUNDLE` (File)
and `RENOVATE_INTERNAL_HOSTS` on a self-hosted estate with its own CA.
**Build > Pipeline schedules**: one schedule on `main`, for example `0 5 * * 1-5`.

## Preconditions

- The runner accepts `RENOVATE_IMAGE`. Mirror it into your registry if runners may
  pull only from there.
- Self-signed or internal CA: set `CA_BUNDLE`, never `NODE_TLS_REJECT_UNAUTHORIZED=0`.
  `run-local.sh` mounts a copy, so a system file such as
  `/etc/pki/tls/certs/ca-bundle.crt` works under SELinux.
- Each upstream chart repository or registry that `Chart.yaml` and values files name
  is reachable, or aliased to a mirror that lists the same tags.

## Behaviour

- A scheduled, web, API or trigger pipeline runs `renovate`; a push runs only
  `renovate-config-validator` over `config.js` and the presets.
- A project without `renovate.json` gets an onboarding merge request that extends
  `default.json` from this project.
- `default.json`: `config:recommended`, a Dependency Dashboard issue, a 3-day
  `minimumReleaseAge`, no automerge. Container tags without a release timestamp are
  not held back, because most registries and mirrors publish none.
- `helm.json`: `Chart.yaml` dependencies, image tags in `values*.yaml` and
  `environments/**/*.yaml`, any value under a `# renovate: datasource=... depName=...`
  comment, and a patch bump of a chart's own `version` with each change.
- One run at a time (`resource_group: renovate`); the package cache persists in the
  job cache between runs.

## Registry credentials

Two different things need registry credentials, and they read different variables:

- **Version lookups** by Renovate. Renovate makes every registry request itself and
  never reads a `docker login` or `podman login`. It uses only the
  `DOCKER_<HOST>_USERNAME` / `_PASSWORD` pairs (`detectHostRulesFromEnv` in
  `config.js`), one pair per registry host.
- **Pulling `RENOVATE_IMAGE`**. `run-local.sh` logs podman or docker in to the
  image's registry with the `DOCKER_<HOST>` pair for that host, so one pair serves both
  and no manual `podman login` is needed. A docker or kubernetes executor pulls the job
  image with `DOCKER_AUTH_CONFIG` instead.

## Out of scope

- Merging: every update is a merge request for review.
- Mirroring images or charts into your registry.
- Release notes from github.com (`fetchChangeLogs: off`).

## Expected result

Merge requests titled `Update <dependency> ... (<chart directory>)` in each opted-in
project, and a **Dependency Dashboard** issue listing the rest. `./run-local.sh --dry-run`
prints `DRY-RUN: Would commit files to branch renovate/...` for each update, and no `WARN`.
