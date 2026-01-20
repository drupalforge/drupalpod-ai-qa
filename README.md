# DrupalPod AI QA

A build system for QA testing in the Drupal AI ecosystem.

## What This Does

Creates Drupal environments (CMS or Core) with AI modules pulled directly from 
git.drupalcode.org as submodules. Solves the problem of testing AI module PRs 
where version compatibility between the base `drupal/ai` module and ecosystem 
modules (ai_search, ai_provider_litellm, ai_agents, etc.) needs to be automatically 
resolved.

When you test a PR for `ai_search` that requires `^2.0` of the base AI module, 
the system clones AI at 2.0.x, then filters out ecosystem modules that only 
support `^1.2`. All modules are git submodules with live symlinks: edit code
and see changes immediately.

## Quick Start

```bash
# Clone the repository
git clone <repo-url>
cd drupalpod-ai-qa

# Start DDEV
ddev start

# Access the site
open https://drupalpod-ai-qa.ddev.site
# Credentials: admin / admin
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
  - DP_FORCE_DEPENDENCIES=1
  - DP_REBUILD=1
```

When using a PR fork/branch, also set a module version
(e.g., `DP_AI_MODULE_VERSION=1.2.x`, `DP_TEST_MODULE_VERSION=1.0.7`)
so Composer can resolve the branch.

Run `ddev restart` to apply changes.

## Configuration Reference

### Core Settings

| Variable | Purpose | Default |
|----------|---------|---------|
| `DP_STARTER_TEMPLATE` | `cms` or `core` | `cms` |
| `DP_VERSION` | Drupal version (e.g., `2.x`, `11.2.8`) | `2.x` for CMS, `11.2.8` for core |
| `DP_REBUILD` | `1` = force clean rebuild | `1` |
| `DP_INSTALL_PROFILE` | Drupal install profile | Auto-detect for CMS, `standard` for core |

### AI Module Settings

| Variable | Purpose | Default |
|----------|---------|---------|
| `DP_AI_MODULE_VERSION` | AI version (empty = auto-detect from test module) | Empty |
| `DP_AI_ISSUE_FORK` | Fork name for AI PR testing | Empty |
| `DP_AI_ISSUE_BRANCH` | Branch name for AI PR testing | Empty |
| `DP_AI_MODULES` | Ecosystem modules to include (allowlisted) | `ai_provider_litellm,ai_search,ai_agents` |
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

## Docker Images

Pre-built images are available on DockerHub for use with DevPanel:

```
drupalforge/drupalpod-ai-qa:php-8.3-cms
drupalforge/drupalpod-ai-qa:php-8.3-core
drupalforge/drupalpod-ai-qa:php-8.2-core
drupalforge/drupalpod-ai-qa:latest  # alias for php-8.3-cms
```

Images are built via GitHub Actions on push to `main`. Each image contains a fully installed Drupal site with AI modules pre-configured.

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
└── logs/                        # Build logs + cache
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

Resolution caches Composer artifacts and base project skeletons under `logs/cache`
to speed up repeated runs. Remove that directory to start fresh.

### Working with Cloned Modules

Modules in `repos/` are symlinked to `docroot/web/modules/contrib/`. Changes are live:

```bash
ddev ssh
cd repos/ai_search
git checkout -b my-branch
# Make changes - they're immediately live in Drupal
```

## Troubleshooting

**Version conflict error**
```
ERROR: Version Conflict
Test module 'ai_search' requires AI 2.0.x
But you explicitly configured DP_AI_MODULE_VERSION=1.2.x
```
Remove `DP_AI_MODULE_VERSION` to auto-detect, or set it to match.

**Module skipped warning**
```
Incompatible: ai_search requires AI ^2.0, but we have AI 1.2.x
```
Expected behavior - the module is incompatible and correctly excluded. Still cloned to `repos/` for inspection.

**Build failures**

Check `logs/init-*.log` for detailed output. Common issues:
- Git fetch failures (network/auth)
- Composer dependency conflicts
- Database connection problems

**Debugging version detection**
```bash
ddev ssh
cd repos/ai
git describe --tags
git branch -r --contains HEAD
```

## Running Tests

```bash
npm test
```

BATS test suite validates setup script logic without requiring full Drupal installs.
