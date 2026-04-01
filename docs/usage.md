# Usage

This project supports both local DDEV usage and DevPanel/DrupalForge images.

## DDEV (Local)

Create `.ddev/config.drupal.yaml` for overrides:

```yaml
web_environment:
  - DP_STARTER_TEMPLATE=cms
  - DP_VERSION=
  - DP_AI_MODULE=ai
  - DP_AI_MODULE_VERSION=
  - DP_AI_PROVIDER=anthropic
  - DP_TEST_MODULE=ai_image_alt_text
  - DP_TEST_MODULE_VERSION=1.0.x
  - DP_TEST_MODULE_ISSUE_FORK=ai_image_alt_text-3545687
  - DP_TEST_MODULE_ISSUE_BRANCH=3545687-500-error-on-large-nodes
  - DP_FORCE_DEPENDENCIES=1
  - DP_REBUILD=1
  - DP_NO_DEV=0
```

Apply changes:

```bash
ddev restart
```

## DevPanel / DrupalForge Images

Alternatively, you can spin up a machine with DrupalForge at https://www.drupalforge.org/drupalpod,
using parameters:
```yaml
APP_ROOT=/var/www/html
COMPOSER_ROOT=/var/www/html/docroot
DP_WEB_ROOT=/var/www/html/docroot/web
DP_REPO_BRANCH=https://github.com/drupalforge/drupalpod-ai-qa/tree/1.0.x
DP_IMAGE=drupalforge/drupalpod-ai-qa:php-8.3-[DP_STARTER_TEMPLATE]
DP_RUN_SCRIPT=init.sh
DP_STARTER_TEMPLATE=
DP_VERSION=
DP_AI_MODULE=
DP_AI_MODULE_VERSION=
DP_AI_ISSUE_FORK=
DP_AI_ISSUE_BRANCH=
DP_EXTRA_MODULES=ai_search,ai_agents,ai_provider_amazeeio,ai_image_alt_text
DP_TEST_MODULE=
DP_TEST_MODULE_VERSION=
DP_TEST_MODULE_ISSUE_FORK=
DP_TEST_MODULE_ISSUE_BRANCH=
DP_FORCE_DEPENDENCIES=1
DP_NO_DEV=0
```

## Flow (High-Level)

1. `scripts/fallback_setup.sh` sets defaults and validates inputs.
2. `scripts/resolve_modules.sh` resolves versions via Composer and writes a plan.
3. `scripts/clone_modules.sh` checks out git repos based on that plan.
4. `scripts/composer_setup.sh` builds the Drupal project and adds path repos.

The plan is written to `logs/ai-manifest.json` and drives module checkout.

## Compatibility & Overrides

- If `DP_TEST_MODULE` is set, it drives AI compatibility.
- Optional modules in `DP_EXTRA_MODULES` are tried and skipped if incompatible (capped by MAX_EXTRA_MODULES in fallback_setup.sh).
- `DP_FORCE_DEPENDENCIES=1` enables a local Composer plugin that relaxes
  `drupal/ai` constraints during resolution (useful for AI 2.x on CMS).
- When using PR branches, set both fork + branch and a matching module version
  (e.g., `DP_AI_ISSUE_FORK=drupal`, `DP_AI_ISSUE_BRANCH=3512345-bugfix`,
  `DP_AI_MODULE_VERSION=1.2.x`). Missing versions/branches now hard-fail.

## Configuration Variables

Common variables:

- `DP_STARTER_TEMPLATE`: `cms` or `core`
- `DP_VERSION`: version string (empty = latest stable)
- `DP_AI_MODULE_VERSION`: empty = auto-detect; set to force a version
- `DP_AI_PROVIDER`: `openai`, `anthropic`, or `amazee`
- `DP_AI_PROVIDER` aliases: `claude` -> `anthropic`, `amazeeai`/`amazeeio` -> `amazee`
- `DP_AI_PROVIDER=openai|anthropic` enables the DrupalPod AI QA key prompt flow
- `DP_AI_PROVIDER=amazee` keeps the native amazee recipe/provisioning flow
- `DP_EXTRA_MODULES`: extra modules to include, up to 15 (see `README.md`)
- `DP_TEST_MODULE`: module under test (optional)
- `DP_FORCE_DEPENDENCIES`: `1` to relax `drupal/ai` constraints via local plugin
- `DP_NO_DEV`: `1` to skip dev dependencies for faster installs
