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
| `DP_EXTRA_MODULES` | Extra modules to include (comma-separated, capped by MAX_EXTRA_MODULES) | `ai_search,ai_agents,ai_provider_amazeeio,ai_image_alt_text` |
| `DP_FORCE_DEPENDENCIES` | `1` = lenient mode (relax constraints), `0` = strict | `1` |

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

**When to disable (set to `0`):**
- Testing strict semver compatibility
- Validating that modules satisfy their declared constraints
- Production-like dependency resolution

The local plugin lives at `src/ai-lenient-plugin/`. See https://github.com/mglaman/composer-drupal-lenient
for the upstream inspiration.

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
│   └── composer_setup.sh        # Generate composer.json + path repos
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
7. **AI provider setup** - Enables the provider module and `drupalpod_ai_qa` if `DP_AI_PROVIDER` is set; a Drush command applies the provider configuration

### Version Resolution

`resolve_modules.sh` builds a temporary Composer project to resolve concrete
module versions against the selected template and constraints. It writes a plan
to `logs/ai-manifest.json` that `clone_modules.sh` uses to check out git repos.

When `DP_TEST_MODULE` is set:

1. The test module drives compatibility for `drupal/ai`
2. Optional ecosystem modules are tested for compatibility and skipped if incompatible
3. The resolved plan includes AI + the test module + any compatible optional modules

When `DP_FORCE_DEPENDENCIES=1` (default):

1. Lenient plugins are installed to `vendor/` and activated
2. Constraints on `drupal/ai` and test modules are relaxed to `*` (any version)
3. For CMS templates, AI resolution happens against Core (bypassing `drupal_cms_ai`)
4. Optional modules are still tested for genuine compatibility using `--no-plugins`

This allows forcing incompatible versions (e.g., AI 2.0.x + ai_context 1.0.x which requires AI ^1.3)
while still intelligently skipping truly incompatible optional modules.


### Working with Cloned Modules

Modules in `repos/` are symlinked to `docroot/web/modules/contrib/`. Changes are live:

```bash
ddev ssh
cd repos/ai_search
git checkout -b my-branch
# Make changes - they're immediately live in Drupal
```
