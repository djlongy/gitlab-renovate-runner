// Self-hosted Renovate for any GitLab. Nothing site-specific lives in this
// file: the endpoint, token, scope, proxy, registry credentials and aliases all
// come from the environment (CI/CD variables in the runner project). Renovate
// reads its own RENOVATE_* variables and they override what is set here.
//
// See README.md for the variables and docs/howto-helm-chart-updates.md for a
// deployment walkthrough.

const env = process.env;

function jsonVariable(name, fallback) {
  if (!env[name]) {
    return fallback;
  }
  try {
    return JSON.parse(env[name]);
  } catch (error) {
    throw new Error(`${name} is not valid JSON: ${error.message}`);
  }
}

// The project holding default.json and helm.json. In CI it is this project;
// run from a workstation, set RENOVATE_PRESET_REPO to its path.
const presetRepo = env.RENOVATE_PRESET_REPO || env.CI_PROJECT_PATH;
const endpoint = env.RENOVATE_ENDPOINT || env.CI_API_V4_URL;

// Hosts on private addresses that Renovate may call: the GitLab endpoint, plus
// RENOVATE_INTERNAL_HOSTS (comma list, e.g. "registry.example.com,charts.example.com";
// a bare name means https://, give http://host:port for anything else). Each
// becomes a URL-prefix rule, which also covers presets fetched from that host.
// Only global config can grant this: allowInternal in a project's renovate.json
// is ignored.
const internalHosts = (env.RENOVATE_INTERNAL_HOSTS || '')
  .split(',')
  .map((host) => host.trim())
  .filter(Boolean);

module.exports = {
  platform: 'gitlab',
  // In CI the endpoint is this GitLab; elsewhere set RENOVATE_ENDPOINT.
  ...(endpoint ? { endpoint } : {}),

  hostRules: [
    ...(endpoint ? [{ matchHost: new URL(endpoint).origin, allowInternal: true }] : []),
    ...internalHosts.map((host) => ({
      matchHost: host.includes('://') ? host : `https://${host}`,
      allowInternal: true,
    })),
  ],

  // Every project the bot user is a member of, narrowed by
  // RENOVATE_AUTODISCOVER_FILTER (for example "platform/**"). For one project
  // only: RENOVATE_AUTODISCOVER=false and RENOVATE_REPOSITORIES=group/project.
  autodiscover: true,
  forkProcessing: 'disabled',

  onboardingConfig: {
    $schema: 'https://docs.renovatebot.com/renovate-schema.json',
    extends: presetRepo ? [`local>${presetRepo}`] : ['config:recommended'],
  },

  // Registry credentials from variables named <TYPE>_<HOST>_USERNAME and
  // <TYPE>_<HOST>_PASSWORD, host with dots and dashes as underscores:
  //   DOCKER_REGISTRY_EXAMPLE_COM_USERNAME / DOCKER_REGISTRY_EXAMPLE_COM_PASSWORD
  //   HELM_CHARTS_EXAMPLE_COM_USERNAME / HELM_CHARTS_EXAMPLE_COM_PASSWORD
  detectHostRulesFromEnv: true,

  // Map a mirror prefix to the registry it mirrors, as JSON, e.g.
  //   {"registry.example.com/dockerhub": "docker.io"}
  // Lookups then go to the upstream (through the proxy) while the files keep
  // naming the mirror. See the howto for when to alias and when not to.
  registryAliases: jsonVariable('RENOVATE_REGISTRY_ALIASES_JSON', {}),

  // The -full image carries every package manager's tooling, so nothing is
  // downloaded from the internet at run time.
  binarySource: 'global',

  // Release notes come from github.com; most air-gapped sites cannot reach it.
  fetchChangeLogs: env.RENOVATE_FETCH_CHANGE_LOGS || 'off',

  // default.json lets container tags without a release timestamp through (most
  // registries publish none); Renovate reports each as a warning. It is expected.
  logLevelRemap: [{ matchMessage: '/did not have a releaseTimestamp/', newLogLevel: 'info' }],
};
