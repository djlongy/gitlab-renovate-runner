# gitlab-renovate-runner

Runs Renovate on a schedule against your GitLab projects, with shared presets for Helm deployment repositories.

## Requirements

- GitLab with a bot user, member (Developer) of every project Renovate may update.
- A runner that can pull `RENOVATE_IMAGE` (about 10 GB) and reach GitLab, plus the
  upstream registries directly or through an HTTP proxy. Where only a desktop has
  the proxy, `run-local.sh` runs the same configuration with podman or docker.

## CI/CD variables

Set on this project. The full set of Renovate options readable from the
environment is Renovate's own `RENOVATE_*` list; `config.js` holds the defaults.

| Req | Name | Default | Purpose |
|---|---|---|---|
| Required | `RENOVATE_TOKEN` | none | Bot user's token: `api`, `read_repository`, `write_repository`. Masked |
| Optional | `RENOVATE_AUTODISCOVER_FILTER` | every project the bot sees | Scope, e.g. `platform/**` |
| Optional | `HTTPS_PROXY`, `HTTP_PROXY`, `NO_PROXY` | none | Proxy for registry lookups. Put the GitLab host in `NO_PROXY` |
| Optional | `CA_BUNDLE` | image store | File variable: internal CA bundle for GitLab, the proxy and mirrors |
| Optional | `RENOVATE_REGISTRY_ALIASES_JSON` | `{}` | Mirror prefix to upstream, e.g. `{"registry.example.com/dockerhub":"docker.io"}` |
| When private registry | `DOCKER_<HOST>_USERNAME`, `DOCKER_<HOST>_PASSWORD` | none | Credentials, host with `.` and `-` as `_`. `HELM_` and `PYPI_` prefixes work the same way |
| Optional | `RENOVATE_IMAGE` | `renovate/renovate:<pinned>-full` | Job image; point it at your internal registry |
| Optional | `RENOVATE_DRY_RUN` | unset | `full` looks everything up and opens nothing |
| Optional | `LOG_LEVEL` | `info` | `debug` lists every dependency found |

## Usage

A project opts in with a `renovate.json` on its default branch:

```json
{
  "extends": [
    "local>platform/renovate-runner",
    "local>platform/renovate-runner:helm"
  ]
}
```

## Minimum configuration

In this project, **Settings > CI/CD > Variables**: `RENOVATE_TOKEN` (masked), and
`HTTPS_PROXY` plus `NO_PROXY=gitlab.example.com` if lookups go through a proxy.
**Build > Pipeline schedules**: one schedule on `main`, for example `0 5 * * 1-5`.

## Preconditions

- The runner accepts `RENOVATE_IMAGE`. Mirror it into your registry if runners may
  pull only from there.
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

## Out of scope

- Merging: every update is a merge request for review.
- Mirroring images or charts into your registry.
- Release notes from github.com (`fetchChangeLogs: off`).

## Expected result

Merge requests titled `Update <dependency> ... (<chart directory>)` in each opted-in
project, and a **Dependency Dashboard** issue listing the rest. From a workstation:

```bash
RENOVATE_ENDPOINT=https://gitlab.example.com/api/v4 RENOVATE_PRESET_REPO=platform/renovate-runner ./run-local.sh --dry-run
```

prints `DRY-RUN: Would commit files to branch renovate/...` for each update.
