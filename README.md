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

- The runner may pull `RENOVATE_IMAGE`. Mirror it where runners pull only from yours.
- Each upstream chart repository or registry that `Chart.yaml` and values files name
  is reachable, or aliased to a mirror that lists the same tags.

## Behaviour

- A schedule, web, API or trigger pipeline runs `renovate`. A push only validates.
- A project without `renovate.json` gets an onboarding MR extending `default.json`.
- `default.json` and `helm.json` state what each preset does in their `description`s.
- One run at a time (`resource_group: renovate`); the package cache persists in the
  job cache between runs.

## Registry credentials

- **Lookups**: Renovate never reads a `docker login` or `podman login`, only the
  `DOCKER_<HOST>_USERNAME` / `_PASSWORD` pairs, one per registry host.
- **Pulling `RENOVATE_IMAGE`**: `run-local.sh` logs in with the pair for the image's
  host, so no manual `podman login`. A docker executor uses `DOCKER_AUTH_CONFIG`.

## Internal hosts and certificates

- Renovate warns on every request to a private address (`internalHostAccess`, default
  `warn`, `block` from v45). `config.js` grants the GitLab endpoint and each
  `RENOVATE_INTERNAL_HOSTS` entry as a URL prefix, which also covers presets served
  from that host. A `DOCKER_<HOST>` pair grants its host too.
- Only this global config can grant a host. `hostRules` with `allowInternal` in a
  project's `renovate.json` fails validation and Renovate skips that project.
- With no warning left in a run, set `RENOVATE_INTERNAL_HOST_ACCESS=block`. Avoid
  `allow`: any project could reach any internal service, and v46 removes it.
- `CA_BUNDLE` is appended to the image's public roots and reaches Renovate
  (`NODE_EXTRA_CA_CERTS`), git (`GIT_SSL_CAINFO`) and helm, go and pip
  (`SSL_CERT_FILE`). Include intermediates. Java tooling reads its own keystore.
  `run-local.sh` mounts a copy, so `/etc/pki/tls/certs/ca-bundle.crt` works under SELinux.
- Never set `NODE_TLS_REJECT_UNAUTHORIZED=0`: it turns off verification for every host.
  `hostRules[].httpsCertificateAuthority` covers Renovate's own requests, not git or helm.

## Out of scope

- Merging: every update is a merge request for review.
- Mirroring images or charts into your registry.
- Release notes from github.com (`fetchChangeLogs: off`).

## Expected result

Merge requests titled `Update <dependency> ... (<chart directory>)` in each opted-in
project, and a **Dependency Dashboard** issue listing the rest. `./run-local.sh --dry-run`
prints `DRY-RUN: Would commit files to branch renovate/...` for each update, and no `WARN`.
