# Keep Helm charts and their images current with Renovate

This guide takes you from an empty GitLab to merge requests that move chart versions
and image tags for a deployment repository like `examples/helm-deployments/` (NiFi,
Redis, CloudNativePG). It assumes an air-gapped network whose only way out is an HTTP
proxy.

## 1. Lay the deployment repository out so Renovate can see everything

Renovate updates only what a manager extracts and a datasource resolves. Both fail
quietly, so the layout matters more than the configuration.

```text
charts/<app>/Chart.yaml          dependencies: name, version, repository
charts/<app>/values.yaml         image: {registry, repository, tag}
environments/<env>/<app>.yaml    per-environment overrides
renovate.json                    extends the runner's presets
```

| You pin | Write it as | Found by |
|---|---|---|
| An upstream chart you wrap | `dependencies:` in `Chart.yaml`, `repository: https://...` or `oci://...` | `helmv3` |
| An image the chart runs | `image.repository` + `image.tag` (and optional `image.registry`) in a values file | `helm-values` |
| A value no manager recognises | the line under `# renovate: datasource=docker depName=<image>` | `helm.json`'s regex manager |
| A CloudNativePG `Cluster` image | `imageName: ghcr.io/cloudnative-pg/postgresql:16.2` | the regex manager in the example's `renovate.json` |

Rules that keep extraction working:

- Literal values only. `tag: {{ .Values.global.tag }}` or `image: ${IMAGE}` is
  invisible; use a `# renovate:` comment when a value must stay indirect.
- One image per `image:` block. `repository` without `tag` is skipped.
- A chart you own with no upstream chart (NiFi in the example) still gets image
  updates from its values file; there is simply no `dependencies:` entry.

## 2. Decide where the lookups go

Renovate looks up versions from where the file points. Pick one approach per
registry:

- **Upstream through the proxy.** Files name `docker.io/...`, `ghcr.io/...`,
  `https://cloudnative-pg.github.io/charts`. The runner (or desktop) sets
  `HTTPS_PROXY`. Simplest, and the tag lists are complete.
- **Your mirror, aliased to upstream.** Files name `registry.example.com/dockerhub/apache/nifi`
  because that is what the cluster pulls. Set
  `RENOVATE_REGISTRY_ALIASES_JSON={"registry.example.com/dockerhub":"docker.io"}` and
  lookups go upstream while the files keep the mirror prefix.
- **Your mirror, queried directly.** Works only when the mirror lists upstream tags
  it has not cached (an Artifactory or Nexus remote does). A pull-through cache that
  lists only what someone already pulled (a Harbor proxy project or a Quay proxy-cache
  organisation does) never shows a newer tag, so Renovate reports nothing and the run
  is still green. Measured on a Quay proxy-cache organisation for Docker Hub:
  `tags/list` for `library/alpine` returned `["3.19"]`, the one tag pulled through
  it, against 224 on Docker Hub.

An alias key matches the registry as the file writes it. `FROM alpine:3.19` names no
registry, so an alias keyed `docker.io` does not match it and its lookup still goes
to Docker Hub; `FROM docker.io/library/alpine:3.19` does match.

Credentials for a private registry or chart repository go in CI/CD variables named
`DOCKER_<HOST>_USERNAME` / `_PASSWORD` or `HELM_<HOST>_USERNAME` / `_PASSWORD`, host
with dots and dashes as underscores (`DOCKER_REGISTRY_EXAMPLE_COM_USERNAME`).

## 3. Create the bot user and its token

1. Create a user, for example `renovate-bot`.
2. Add it as **Developer** to the group that holds your deployment repositories.
3. As that user, create a personal access token with `api`, `read_repository` and
   `write_repository`.

## 4. Import the runner

1. Create a project, for example `platform/renovate-runner`, and push this repository
   to it.
2. **Settings > CI/CD > Variables**:
   - `RENOVATE_TOKEN`: the bot token, masked.
   - `HTTPS_PROXY` and `HTTP_PROXY`: `http://proxy.example.com:3128`.
   - `NO_PROXY`: your GitLab host, plus any internal registry you query directly.
   - `CA_BUNDLE` (File type): your internal CA bundle, if GitLab or the proxy uses one.
   - `RENOVATE_AUTODISCOVER_FILTER`: `platform/**` to start small.
   - `RENOVATE_IMAGE`: your mirrored copy of `renovate/renovate:<version>-full`, if
     runners cannot pull from Docker Hub.
3. Run the pipeline once from **Build > Pipelines > Run pipeline** with
   `RENOVATE_DRY_RUN=full` and `LOG_LEVEL=debug`.

When the runners cannot reach the proxy but a desktop can, skip the schedule and run
from the desktop instead:

```bash
export RENOVATE_TOKEN=<bot token>
export RENOVATE_ENDPOINT=https://gitlab.example.com/api/v4
export RENOVATE_PRESET_REPO=platform/renovate-runner
export HTTPS_PROXY=http://proxy.example.com:3128 NO_PROXY=gitlab.example.com
./run-local.sh --dry-run
```

A systemd timer or cron entry running `./run-local.sh` replaces the pipeline schedule.

## 5. Onboard the deployment repository

Commit `renovate.json` to its default branch (Renovate reads configuration from the
default branch only):

```json
{
  "extends": [
    "local>platform/renovate-runner",
    "local>platform/renovate-runner:helm"
  ]
}
```

Add repository-specific managers beside the `extends`, as the example does for the
CloudNativePG `imageName`.

## 6. Read the dry run before trusting it

A green job proves nothing: an unextracted dependency and an unreachable registry
both produce silence. In the debug log, find `packageFiles with updates` and check
that every chart and image you expect is listed with the right `currentValue`. Then
look for these:

| Log line | Meaning | Fix |
|---|---|---|
| `Failed to look up helm package <x>: no-result` | The chart repository did not answer | Check the URL through the proxy, or mirror the chart |
| `Found no results from datasource that look like a version` | The registry answered with no usable tags | Add credentials, or alias to upstream (step 2) |
| an update with `pendingChecks: true` | `minimumReleaseAge` is holding it | Wait, or tick it on the Dependency Dashboard |

## 7. Schedule it

**Build > Pipeline schedules > New schedule** on `main`, for example `0 5 * * 1-5`,
with no dry-run variable. Each run opens or rebases one merge request per update,
titled with the chart directory, for example
`Update Helm release cloudnative-pg to v0.29.0 (cloudnative-pg)`, and bumps that
chart's own `version` in the same commit.

You know it works when the deployment repository has a **Dependency Dashboard** issue
and one open merge request for each outdated chart or image.
