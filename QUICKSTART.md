## What this is

`run-local.sh` runs Renovate in a podman or docker container, from a workstation or a shell runner host. `.gitlab-ci.yml` runs the same thing on a pipeline schedule. Settings come from `.env` locally (template: `.env.example`) and from CI/CD variables in the pipeline. `default.json` and `helm.json` are the presets each project's `renovate.json` extends (template: `examples/renovate.json`). It opens merge requests. It does not merge them or mirror images.

## How to use it

1. Import this repository into your GitLab, for example as `platform/renovate-runner`.
2. On the group Renovate should update, create a bot token: **Settings > Access tokens > Add new token**. Use the name `renovate-bot` (it becomes the bot's display name), role **Developer**, and scopes `api` and `write_repository`. Keep this project inside that group, or the bot cannot read the presets.
3. On the host that runs Renovate, create your settings file: `install -m 600 .env.example .env`
4. Open `.env` and fill in the **Required** block. For a first test, set `RENOVATE_AUTODISCOVER=false` and `RENOVATE_REPOSITORIES=<group>/<project>`. With an internal CA, set `CA_BUNDLE`.
5. Run a dry run: `./run-local.sh --dry-run`
6. Copy the same names into this project's **Settings > CI/CD > Variables**. Make `RENOVATE_TOKEN` masked and `CA_BUNDLE` a **File** variable. Leave out `RENOVATE_ENDPOINT` and `RENOVATE_PRESET_REPO`, because CI fills them in.
7. Add a schedule under **Build > Pipeline schedules**: `0 5 * * 1-5` on `main`.

You know it works when step 5 prints `DRY-RUN: Would commit files to branch renovate/...` and no `WARN` line.

If it fails:
- `WARN: HTTP request to an internal host`: add that host to `RENOVATE_INTERNAL_HOSTS` in `.env`, never to a project's `renovate.json`.
- The image pull is refused: set the `DOCKER_<HOST>_USERNAME` and `DOCKER_<HOST>_PASSWORD` pair for `RENOVATE_IMAGE`'s registry in `.env`.
