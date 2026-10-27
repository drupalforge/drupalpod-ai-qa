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

## Configuration Reference

### Core Settings

| Variable | Purpose                                                               | Default |
|----------|-----------------------------------------------------------------------|---------|
| `DP_STARTER_TEMPLATE` | `cms` or `core`                                                       | `cms` |
| `DP_VERSION` | Drupal version (e.g., `2.x`, `11.2.8`)                                | `2.x` for CMS, `11.2.8` for core |
| `DP_REBUILD` | `1` = force clean rebuild (if 0, prevents destroying project in ddev) | `1` |
| `DP_NO_DEV` | `1` = skip dev dependencies (PHPStan, testing tools) for faster installs | `0` |
| `DP_INSTALL_PROFILE` | Drupal install profile                                                | Auto-detect for CMS, `standard` for core |
| `DP_AI_VIRTUAL_KEY` | Enables automated AI configuration (experimental) | Empty |

Note: `DP_AI_VIRTUAL_KEY` support is not fully integrated or tested yet.

### AI Module Settings

| Variable | Purpose | Default |
|----------|---------|---------|
| `DP_AI_MODULE_VERSION` | AI version (empty = auto-detect from test module) | Empty |
| `DP_AI_ISSUE_FORK` | Fork name for AI PR testing (requires branch) | Empty |
| `DP_AI_ISSUE_BRANCH` | Branch name for AI PR testing (requires fork) | Empty |
| `DP_EXTRA_MODULES` | Extra modules to include (comma-separated, optionally `module:constraint`, capped by MAX_EXTRA_MODULES) | `ai_search,ai_agents,ai_provider_amazeeio,ai_image_alt_text` |
| `DP_FORCE_DEPENDENCIES` | `1` = lenient mode (relax constraints), `0` = strict | `1` |

Extra modules accept Composer constraints, for example `ai_provider_amazeeio:1.2.7`.
Use spaces, not commas, within a constraint. Without a constraint, Composer selects
a compatible release. Image builds preinstall the provider this way (1.2.7 on
PHP 8.2) and leave `DP_TEST_MODULE` and `DP_TEST_MODULE_VERSION` for container startup.
The PHP 8.2 image allows advisory SA-CONTRIB-2026-134 to avoid blocking this
PHP-compatible release; Composer still reports the advisory during audits.

### Test Module Settings

| Variable | Purpose | Default |
|----------|---------|---------|
| `DP_TEST_MODULE` | Module being tested (drives version resolution) | Empty |
| `DP_TEST_MODULE_VERSION` | Test module version | Empty |
| `DP_TEST_MODULE_ISSUE_FORK` | Fork name for test module PR (requires branch) | Empty |
| `DP_TEST_MODULE_ISSUE_BRANCH` | Branch name for test module PR (requires fork) | Empty |

### Lenient Mode (DP_FORCE_DEPENDENCIES)

**Default: Enabled (`DP_FORCE_DEPENDENCIES=1`)**

Lenient mode relaxes Drupal package version constraints during dependency resolution,
allowing you to force incompatible module combinations together for QA testing. This is
essential when testing patches, PRs, or new versions that may not yet satisfy strict
semver constraints.

**How it works:**

Two Composer plugins work together to relax constraints:

1. **mglaman/composer-drupal-lenient** - Broad ecosystem relaxation
2. **drupalpod/ai-lenient-plugin** (local) - Custom plugin for AI module constraints

When enabled, these plugins:
- Relax `drupal/ai` version constraints to `*` (any version)
- Allow test modules with incompatible AI requirements (e.g., `ai_context ^1.3`) to install with AI 2.0.x
- Bypass `drupal_cms_ai` version constraints when forcing AI versions on CMS
- Enable QA workflows without manual `composer.json` editing

**Example use cases:**
```yaml
# Force AI 2.0.x with ai_context (which requires AI ^1.3)
- DP_AI_MODULE_VERSION=2.0.x
- DP_TEST_MODULE=ai_context
- DP_TEST_MODULE_VERSION=1.0.x
- DP_FORCE_DEPENDENCIES=1  # Allows incompatible versions

# Test CMS 1.x with AI 2.0.x (bypasses drupal_cms_ai ^1.x constraint)
- DP_STARTER_TEMPLATE=cms
- DP_VERSION=1.x
- DP_AI_MODULE_VERSION=2.0.x
- DP_FORCE_DEPENDENCIES=1
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
