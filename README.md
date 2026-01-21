# DrupalPod AI QA

A build system for QA testing in the Drupal AI ecosystem.

## What This Does

Creates Drupal environments (CMS or Core) with AI modules pulled directly from
git.drupalcode.org as submodules. It is designed to streamline QA by letting
you pin exact versions, test forks/branches, and validate compatibility quickly.

You can drop in a fork + branch (plus version) and the system resolves a
compatible set of AI modules automatically. If a module is incompatible, it is
skipped so testing can proceed without manual Composer wrangling.

Example: testing `ai_search` for `^2.0` will check out AI 2.0.x and skip modules
that only support `^1.2`. All modules are git submodules with live symlinks,
so edits are immediate.

Goal: make it fast and safe to QA Drupal core/CMS + AI module combinations and
PR branches without hand-editing constraints.

## Quick Start

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

**Test a contrib module PR (e.g., ai_search)**
```yaml
web_environment:
  - DP_TEST_MODULE=ai_search
  - DP_TEST_MODULE_ISSUE_FORK=drupal
  - DP_TEST_MODULE_ISSUE_BRANCH=3498765-feature-name
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
  - DP_TEST_MODULE=ai_search
  - DP_TEST_MODULE_ISSUE_FORK=drupal
  - DP_TEST_MODULE_ISSUE_BRANCH=3498765-feature
  - DP_AI_MODULE_VERSION=2.0.x
  - DP_FORCE_DEPENDENCIES=1 # This is used as CMS may not be compatible with AI 2.0.x yet
  - DP_REBUILD=1
```

When using a PR fork/branch, also set a module version
(e.g., `DP_AI_MODULE_VERSION=1.2.x`, `DP_TEST_MODULE_VERSION=1.0.7`)
so Composer can resolve the branch.

Run `ddev restart` to apply changes.

## Docs

- `docs/usage.md` — DDEV/DevPanel setup, flow, and configuration notes.
- `docs/development.md` — developer notes and script reference.
- `docs/testing.md` — test suite and scenario runner details.
- `docs/troubleshooting.md` — common build and runtime issues.

## Configuration Reference

### Core Settings

| Variable | Purpose                                                               | Default |
|----------|-----------------------------------------------------------------------|---------|
| `DP_STARTER_TEMPLATE` | `cms` or `core`                                                       | `cms` |
| `DP_VERSION` | Drupal version (e.g., `2.x`, `11.2.8`)                                | `2.x` for CMS, `11.2.8` for core |
| `DP_REBUILD` | `1` = force clean rebuild (if 0, prevents destroying project in ddev) | `1` |
| `DP_INSTALL_PROFILE` | Drupal install profile                                                | Auto-detect for CMS, `standard` for core |
| `DP_AI_VIRTUAL_KEY` | Enables automated AI configuration (experimental) | Empty |

Note: `DP_AI_VIRTUAL_KEY` support is not fully integrated or tested yet.

### AI Module Settings

| Variable | Purpose | Default |
|----------|---------|---------|
| `DP_AI_MODULE_VERSION` | AI version (empty = auto-detect from test module) | Empty |
| `DP_AI_ISSUE_FORK` | Fork name for AI PR testing | Empty |
| `DP_AI_ISSUE_BRANCH` | Branch name for AI PR testing | Empty |
| `DP_AI_MODULES` | Ecosystem modules to include (allowlisted) | `ai_provider_amazeeio,ai_search,ai_agents` |
| `DP_FORCE_DEPENDENCIES` | `1` = bypass CMS/core constraints (lenient mode) | `0` |

### Test Module Settings

| Variable | Purpose | Default |
|----------|---------|---------|
| `DP_TEST_MODULE` | Module being tested (drives version resolution) | Empty |
| `DP_TEST_MODULE_VERSION` | Test module version | Empty |
| `DP_TEST_MODULE_ISSUE_FORK` | Fork name for test module PR | Empty |
| `DP_TEST_MODULE_ISSUE_BRANCH` | Branch name for test module PR | Empty |

### Configuration Files

- **`.ddev/config.yaml`** - System defaults (don't edit)
- **`.ddev/config.drupal.yaml`** - Your overrides (create this)
- **`.ddev/config.drupalpod.yaml`** - DevPanel/DrupalForge overrides

## Docker Images

Pre-built images are available on DockerHub for use with DevPanel:

```
drupalforge/drupalpod-ai-qa:php-8.3-cms
drupalforge/drupalpod-ai-qa:php-8.3-core
drupalforge/drupalpod-ai-qa:php-8.2-core
drupalforge/drupalpod-ai-qa:latest  # alias for php-8.3-cms
```

Images are built via GitHub Actions on push to `1.0.x`. Each image contains a fully installed Drupal site with AI modules pre-configured.

## Technical Reference

### Directory Structure

```
drupalpod-ai-qa/
├── .ddev/
│   ├── config.yaml              # System defaults + DDEV config
│   └── config.drupal.yaml       # User overrides (create this)
├── .devpanel/                   # Docker/build scripts + DevPanel assets
├── scripts/                     # Setup scripts
│   ├── init.sh                  # Main orchestrator
│   ├── fallback_setup.sh        # Default env vars + validation
│   ├── resolve_modules.sh       # Composer resolution + plan
│   ├── clone_modules.sh         # Git cloning based on plan
│   ├── composer_setup.sh        # Generate composer.json + path repos
│   └── setup_ai.sh              # Configure AI settings
├── repos/                       # Git submodules (AI modules cloned here)
├── docroot/                     # Drupal install (generated, gitignored)
├── tests/                       # BATS test suite + scenario runner
└── logs/                        # Build logs
```

### Script Orchestration

`scripts/init.sh` runs these steps in order:

1. **fallback_setup.sh** - Sets defaults, validates template/version combinations
2. **resolve_modules.sh** - Resolves module versions and writes a manifest
3. **clone_modules.sh** - Clones AI modules defined in the manifest
4. **composer_setup.sh** - Creates Drupal project, adds path repositories
5. **Composer operations** - Runs `composer update`
6. **Drupal installation** - Runs `drush site-install`
7. **setup_ai.sh** - Configures AI settings if `DP_AI_VIRTUAL_KEY` is set

### Version Resolution

`resolve_modules.sh` builds a temporary Composer project to resolve concrete
module versions against the selected template and constraints. It writes a plan
to `logs/ai-manifest.json` that `clone_modules.sh` uses to check out git repos.

When `DP_TEST_MODULE` is set:

1. The test module drives compatibility for `drupal/ai`
2. Optional ecosystem modules are skipped (so they don't block the test)
3. The resolved plan still includes AI + the test module

When `DP_FORCE_DEPENDENCIES=1`, resolution can bypass CMS/core constraints using
lenient mode to allow explicit tests (e.g., AI 2.x against CMS 1.x).


### Working with Cloned Modules

Modules in `repos/` are symlinked to `docroot/web/modules/contrib/`. Changes are live:

```bash
ddev ssh
cd repos/ai_search
git checkout -b my-branch
# Make changes - they're immediately live in Drupal
```
