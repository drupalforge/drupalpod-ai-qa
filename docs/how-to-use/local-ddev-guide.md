# Local DDEV Guide

This page is for users who want to run DrupalPod AI QA locally instead of using
DrupalForge.

## Step 1: Clone the Repository

```bash
git clone <repo-url>
cd drupalpod-ai-qa
```

## Step 2: Authenticate for Git Access

If local setup needs access to private or rate-limited git operations, run:

```bash
ddev auth ssh
```

This is the current answer to the earlier local-permissions problem. You do not
normally need a separate custom token for the standard flow.

## Step 3: Configure Overrides

Create `.ddev/config.drupal.yaml` and only set the values you actually need.

Example:

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

If you need to choose a provider explicitly, see
[Choosing an AI Provider](provider-selection.md).

## Step 4: Start or Rebuild the Environment

```bash
ddev start
```

If you changed overrides and need them applied again:

```bash
ddev restart
```

## Step 5: Access the Site

Open the local site in your browser:

```text
https://drupalpod-ai-qa.ddev.site
```

Default credentials:

- Username: `admin`
- Password: `admin`

## Common Local Workflows

### Test a base AI issue branch

```yaml
web_environment:
  - DP_AI_ISSUE_FORK=drupal
  - DP_AI_ISSUE_BRANCH=3512345-bugfix
  - DP_AI_MODULE_VERSION=1.2.x
  - DP_REBUILD=1
```

### Test a contrib module issue branch

```yaml
web_environment:
  - DP_TEST_MODULE=ai_image_alt_text
  - DP_TEST_MODULE_VERSION=1.0.x
  - DP_TEST_MODULE_ISSUE_FORK=ai_image_alt_text-3545687
  - DP_TEST_MODULE_ISSUE_BRANCH=3545687-500-error-on-large-nodes
  - DP_REBUILD=1
```

### Test a contrib issue against a forced AI version

```yaml
web_environment:
  - DP_TEST_MODULE=ai_agents
  - DP_TEST_MODULE_VERSION=1.0.x
  - DP_TEST_MODULE_ISSUE_FORK=ai_agents-3568673
  - DP_TEST_MODULE_ISSUE_BRANCH=3568673-scope-plugins
  - DP_AI_MODULE_VERSION=2.0.x
  - DP_FORCE_DEPENDENCIES=1
  - DP_REBUILD=1
```

## Rules That Matter

- If you use a fork, also set the matching branch
- If you use a fork and branch, also set the matching module version
- If you leave version fields empty, the resolver will auto-detect where possible
- `DP_TEST_MODULE` drives AI compatibility resolution when it is set
- `DP_FORCE_DEPENDENCIES=1` allows lenient QA combinations that are not yet strict semver matches

## Optional Extra Modules

`DP_EXTRA_MODULES` lets you ask the build to include additional AI ecosystem
modules beyond the main module under test.

Example:

```yaml
web_environment:
  - DP_EXTRA_MODULES=ai_search,ai_agents,ai_provider_amazeeio,ai_image_alt_text
```

This is useful when you want a broader QA environment with common companion
modules available.

Important notes:

- This setting is available in local configuration, even though it is not currently exposed in the Chrome extension
- Extra modules are still checked for compatibility and may be skipped if they do not match the resolved AI version
- This setting is most useful for local DDEV workflows and advanced hosted setups

If you need the full variable reference for DDEV or DrupalForge, see
[Configuration Reference](configuration-reference.md).
