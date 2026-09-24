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

module.exports = {
  platform: 'gitlab',
  // In CI the endpoint is this GitLab; elsewhere set RENOVATE_ENDPOINT.
  ...(env.CI_API_V4_URL ? { endpoint: env.CI_API_V4_URL } : {}),

  // Every project the bot user is a member of, narrowed by
  // RENOVATE_AUTODISCOVER_FILTER (for example "platform/**").
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
};
