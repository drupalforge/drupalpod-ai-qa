# Configuration Reference

This page collects the main environment variables used by DrupalPod AI QA.

Use it when you need to understand or override the build inputs directly.

## Local DDEV Overrides

For local use, create `.ddev/config.drupal.yaml` and add values under
`web_environment`.

Example:

```yaml
web_environment:
  - DP_STARTER_TEMPLATE=cms
  - DP_VERSION=
  - DP_AI_MODULE=ai
  - DP_AI_MODULE_VERSION=
  - DP_TEST_MODULE=ai_image_alt_text
  - DP_TEST_MODULE_VERSION=1.0.x
  - DP_FORCE_DEPENDENCIES=1
  - DP_REBUILD=1
```

## DrupalForge / DevPanel Variables

If you are using DrupalForge or DevPanel rather than DDEV, the environment can
be launched with variables like these:

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

## Core Variables

- `DP_STARTER_TEMPLATE`: `cms` or `core`
- `DP_VERSION`: Drupal version string, or empty for the default resolution path
- `DP_REBUILD`: `1` to rebuild the environment from scratch
- `DP_NO_DEV`: `1` to skip development dependencies for faster installs

## AI Base Variables

- `DP_AI_MODULE`: base AI module name, normally `ai`
- `DP_AI_MODULE_VERSION`: empty for auto-detect, or set to pin AI
- `DP_AI_ISSUE_FORK`: AI base issue fork name
- `DP_AI_ISSUE_BRANCH`: AI base issue branch name
- `DP_AI_PROVIDER`: `openai`, `anthropic`, or `amazee`

## Module Under Test Variables

- `DP_TEST_MODULE`: optional module under test
- `DP_TEST_MODULE_VERSION`: module version for the issue branch or target release line
- `DP_TEST_MODULE_ISSUE_FORK`: issue fork name for the module under test
- `DP_TEST_MODULE_ISSUE_BRANCH`: issue branch name for the module under test

## Optional Ecosystem Variables

- `DP_EXTRA_MODULES`: comma-separated extra ecosystem modules to try to include
- `DP_FORCE_DEPENDENCIES`: `1` for lenient dependency resolution

## Important Notes

- If you use a fork, also set the matching branch
- If you use a fork and branch, also set the matching version field
- If version fields are left empty, the resolver auto-detects where possible
- Extra modules may still be skipped if they are incompatible with the resolved AI version

For implementation details on how these variables are consumed, see
[Development](../development.md).
