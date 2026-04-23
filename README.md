# DrupalPod AI QA

A build system for QA testing in the Drupal AI ecosystem.

## What This Does

Creates Drupal environments (CMS or Core) with AI modules pulled directly from
git.drupalcode.org as cloned repositories. It is designed to streamline QA by
letting you pin exact versions, test forks and branches, and validate
compatibility quickly.

You can drop in a fork + branch (plus version) and the system resolves a
compatible set of AI modules automatically. If a module is incompatible, it is
skipped so testing can proceed without manual Composer wrangling.

Example: testing `ai_search` for `^2.0` will check out AI 2.0.x and skip modules
that only support `^1.2`. The resolved repositories are cloned into `repos/`
and wired into the generated Drupal codebase, so edits are immediate.

Goal: make it fast and safe to QA Drupal core/CMS + AI module combinations and
PR branches without hand-editing constraints.

## Quick Start

For the full documentation set, see `mkdocs.yml` and the pages under `docs/`.

If you want the local DDEV workflow, start here:

```bash
# Clone the repository
git clone <repo-url>
cd drupalpod-ai-qa

# Configure DDEV overrides
# @see "## How To Use (Quick)" below

# Start DDEV
ddev start

# Access the site
open https://drupalpod-ai-qa.ddev.site
# Credentials: admin / admin
```

## How To Use (Quick)

Create `.ddev/config.drupal.yaml` and set only what you need:

```yaml
web_environment:
  - DP_STARTER_TEMPLATE=cms
  - DP_AI_MODULE_VERSION=1.2.x
  - DP_AI_ISSUE_FORK=drupal
  - DP_AI_ISSUE_BRANCH=3512345-bugfix
  - DP_REBUILD=1
```

Apply changes:

```bash
ddev restart
```

## Testing PRs

Create `.ddev/config.drupal.yaml` to override defaults:

**Test a contrib module PR (e.g., ai_image_alt_text)**
```yaml
web_environment:
  - DP_AI_MODULE=ai
  - DP_AI_MODULE_VERSION=
  - DP_TEST_MODULE=ai_image_alt_text
  - DP_TEST_MODULE_VERSION=1.0.x
  - DP_TEST_MODULE_ISSUE_FORK=ai_image_alt_text-3545687
  - DP_TEST_MODULE_ISSUE_BRANCH=3545687-500-error-on-large-nodes
  - DP_REBUILD=1
```

**Test a base AI module PR**
```yaml
web_environment:
  - DP_AI_ISSUE_FORK=drupal
  - DP_AI_ISSUE_BRANCH=3512345-bugfix
  - DP_AI_MODULE_VERSION=1.2.x
  - DP_REBUILD=1
```

**Test a contrib PR against a specific AI version**
```yaml
web_environment:
  - DP_TEST_MODULE=ai_agents
  - DP_TEST_MODULE_VERSION=1.0.x
  - DP_TEST_MODULE_ISSUE_FORK=ai_agents-3568673
  - DP_TEST_MODULE_ISSUE_BRANCH=3568673-scope-plugins
  - DP_AI_MODULE_VERSION=2.0.x
  - DP_FORCE_DEPENDENCIES=1 # Uses local plugin to relax drupal/ai constraints
  - DP_REBUILD=1
```

When using a PR fork/branch, you must set both fork + branch and a module
version (e.g., `DP_AI_MODULE_VERSION=1.2.x`, `DP_TEST_MODULE_VERSION=1.0.7`)
so Composer can resolve the branch. Missing versions/branches hard-fail.

Run `ddev restart` to apply changes.

## Docs

Documentation source lives under `docs/`.

If you want to publish or preview the docs as a documentation site, the repo
includes a root `mkdocs.yml`.

```bash
python3 -m pip install mkdocs mkdocs-material pymdown-extensions
python3 -m mkdocs serve
```

## Docker Images

Pre-built images are available on DockerHub for use with DevPanel:

```
drupalforge/drupalpod-ai-qa:php-8.3-cms
drupalforge/drupalpod-ai-qa:php-8.3-core
drupalforge/drupalpod-ai-qa:php-8.2-core
drupalforge/drupalpod-ai-qa:latest  # alias for php-8.3-cms
```

Images are built via GitHub Actions on push to `1.0.x`. Each image contains a fully installed Drupal site with AI modules pre-configured.
