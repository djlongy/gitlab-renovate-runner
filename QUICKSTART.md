## What this is

`.gitlab-ci.yml` and `config.js` run Renovate on a schedule against every GitLab project its bot user can see; `default.json` and `helm.json` are the presets projects extend. `run-local.sh` runs the same configuration from a desktop with podman or docker. It opens merge requests; it does not merge them or mirror images. The full deployment walkthrough is `docs/howto-helm-chart-updates.md`.

## How to use it

1. Import this repository as `platform/renovate-runner` in your GitLab.
2. Add CI/CD variables: `RENOVATE_TOKEN` (bot token, masked), `HTTPS_PROXY`, and `NO_PROXY` set to your GitLab host.
3. Copy `examples/helm-deployments/renovate.json` into a deployment repository's default branch.
4. Run a dry run: **Build > Pipelines > Run pipeline** with `RENOVATE_DRY_RUN=full` and `LOG_LEVEL=debug`.
5. Check the `packageFiles with updates` log entry lists every chart and image you expect.
6. Add a pipeline schedule on `main`, for example `0 5 * * 1-5`.

You know it works when the deployment repository has a **Dependency Dashboard** issue and a merge request per outdated chart or image.

If it fails:
- The job cannot pull the image: set `RENOVATE_IMAGE` to your mirrored `renovate/renovate:<version>-full`.
- Runners cannot reach the proxy: run `./run-local.sh` from the desktop instead (see its header).
