# DrupalPod AI QA - Testing Guide

## Overview

DrupalPod AI QA is a flexible testing environment for Drupal CMS/Core with AI modules from git repositories, including specific PR branches. It features intelligent dependency resolution and compatibility filtering.

## Key Features

- **Test-Module-First**: Auto-detects AI version requirements from the module you're testing
- **Compatibility Filtering**: Automatically includes only compatible AI modules
- **Git Submodules**: All AI modules cloned from git for live development
- **Composer Path Repositories**: Changes in git repos immediately reflect in the site
- **Test Suite**: 37+ BATS tests verifying decision logic

## Quick Start

### Test a Specific PR

Edit `.ddev/config.drupal.yaml`:

```yaml
web_environment:
  # Test ai_search PR #123
  - DP_TEST_MODULE=ai_search
  - DP_TEST_MODULE_ISSUE_FORK=drupal
  - DP_TEST_MODULE_ISSUE_BRANCH=3498765-add-search-feature
  # AI version auto-detected from ai_search requirements ✓
```

Run `ddev restart` and access https://drupalpod-ai-qa.ddev.site

**Admin login**: `admin` / `admin`

## Architecture

### 1. Hybrid Dependency Resolution

**Test-Module-First (DP_TEST_MODULE)**:
- Clone the module you're testing first
- Read its `composer.json` to determine AI version requirement
- Auto-detect compatible AI version (unless explicitly overridden)

**Compatibility Filtering (DP_AI_MODULES)**:
- Clone all requested AI modules
- Check each for compatibility with the AI version
- Only add compatible modules to composer
- Skip incompatible ones (with warning)

### 2. Smart Version Detection

**Empty DP_AI_MODULE_VERSION** (recommended):
```yaml
- DP_AI_MODULE_VERSION=   # Auto-detect from test module or use latest stable
```
✓ Auto-detects from `DP_TEST_MODULE` requirements (reads composer.json)
✓ Falls back to **latest stable tag** if no test module (e.g., 1.2.1, not 1.2.x-dev)
✓ Detects actual version after cloning for compatibility filtering
✓ Skips incompatible modules automatically (no composer conflicts!)

**Explicit DP_AI_MODULE_VERSION**:
```yaml
- DP_AI_MODULE_VERSION=1.2.x   # Explicitly set
```
✓ Validates compatibility with `DP_TEST_MODULE`
✗ Fails with clear error if incompatible

### 3. File Structure

```
drupalpod-ai-qa/
├── .ddev/
│   ├── config.yaml              # System defaults (don't edit)
│   └── config.drupal.yaml       # User config (customize this)
├── .devpanel/
│   ├── clone_ai_modules.sh      # Hybrid clone + compatibility logic
│   ├── composer_setup.sh        # Adds compatible modules to composer
│   └── fallback_setup.sh        # Auto-detect AI version from CMS/Core
├── repos/                       # Git submodules (live development)
│   ├── ai/                      # AI base module
│   ├── ai_search/               # AI Search (if compatible)
│   ├── ai_provider_litellm/     # AI Provider (if compatible)
│   └── ai_agents/               # AI Agents (if compatible)
├── tests/                       # BATS test suite
│   ├── clone_ai_modules.bats    # Unit tests
│   ├── fallback_setup.bats      # Version detection tests
│   └── integration.bats         # Integration tests
├── web/                         # Drupal (generated, gitignored)
└── vendor/                      # Composer deps (generated, gitignored)
```

## Configuration

### System Config (.ddev/config.yaml)

**Do not edit** - system defaults:

```yaml
web_environment:
  - DP_STARTER_TEMPLATE=cms
  - DP_VERSION=1.x
  - DP_AI_MODULES=ai_provider_litellm,ai_search,ai_agents  # Compatibility filtered
```

### User Config (.ddev/config.drupal.yaml)

**Customize this** for your testing:

```yaml
web_environment:
  # AI Base Module
  - DP_AI_MODULE=ai
  - DP_AI_MODULE_VERSION=          # Empty = auto-detect (recommended)
  - DP_AI_ISSUE_FORK=
  - DP_AI_ISSUE_BRANCH=

  # Test Module (drives AI version)
  - DP_TEST_MODULE=                # e.g., ai_search, ai_agents
  - DP_TEST_MODULE_VERSION=
  - DP_TEST_MODULE_ISSUE_FORK=
  - DP_TEST_MODULE_ISSUE_BRANCH=

  # Optional
  - DP_AI_VIRTUAL_KEY=sk-your-key
  - DP_REBUILD=1                   # Force clean rebuild
```

## Use Cases

### Example 1: Test ai_search PR (Auto-Detect AI Version)

```yaml
# Test ai_search which requires AI ^2.0
- DP_TEST_MODULE=ai_search
- DP_TEST_MODULE_ISSUE_FORK=drupal
- DP_TEST_MODULE_ISSUE_BRANCH=3498765-feature

# Result:
# ✓ ai_search cloned from PR branch
# ✓ AI version auto-detected as 2.0.x (from ai_search requirements)
# ✓ ai cloned at 2.0.x
# ✓ ai_search added to composer (compatible)
# ✓ ai_provider_litellm skipped (requires AI ^1.2, incompatible)
```

### Example 2: Test AI Base Module PR

```yaml
# Test AI base module PR on CMS 2.x
- DP_AI_MODULE=ai
- DP_AI_ISSUE_FORK=drupal
- DP_AI_ISSUE_BRANCH=3512345-fix-bug

# Result:
# ✓ ai cloned from PR branch at git default branch
# ✓ Compatible modules from DP_AI_MODULES added
```

### Example 3: Explicit AI Version (Validation Mode)

```yaml
# Explicitly set AI version (strict validation)
- DP_AI_MODULE_VERSION=1.2.x     # Explicitly set
- DP_TEST_MODULE=ai_search       # Requires AI ^2.0

# Result:
# ✗ ERROR: Version conflict!
#    ai_search requires AI 2.0.x
#    But you explicitly set DP_AI_MODULE_VERSION=1.2.x
#
# Fix options:
# 1. Remove DP_AI_MODULE_VERSION (auto-detect)
# 2. Change to DP_AI_MODULE_VERSION=2.0.x
# 3. Test a different module compatible with AI 1.2.x
```

### Example 4: No Test Module (Latest Stable Release)

```yaml
# Don't set DP_TEST_MODULE or DP_AI_MODULE_VERSION
# Uses latest stable tag (e.g., 1.2.1)

# Result:
# ✓ AI cloned at latest stable tag (e.g., 1.2.1)
# ✓ Detected AI version: 1.2.x (from tag)
# ✓ ai_provider_litellm added (requires AI ^1.2, compatible!)
# ✓ ai_agents added (requires AI ^1.2, compatible!)
# ✗ ai_search skipped (requires AI ^2.0, incompatible)
# ✓ No composer conflicts - incompatible modules automatically skipped!
```

## Environment Variables

### Core Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DP_STARTER_TEMPLATE` | Base template | `cms` or `core` |
| `DP_VERSION` | CMS/Core version | `2.x`, `1.0.0`, `11.2.8` |
| `DP_AI_MODULE` | AI base module | `ai` (default) |
| `DP_AI_MODULE_VERSION` | AI version (empty = auto) | `1.2.x`, `2.0.x`, or empty |

### Test Module Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DP_TEST_MODULE` | Module to test | `ai_search`, `ai_agents` |
| `DP_TEST_MODULE_VERSION` | Test module version | `1.x`, `2.0.0` |
| `DP_TEST_MODULE_ISSUE_FORK` | Issue fork | `drupal` |
| `DP_TEST_MODULE_ISSUE_BRANCH` | PR branch | `3498765-feature` |

### AI Base Module Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `DP_AI_ISSUE_FORK` | AI module fork | `drupal` |
| `DP_AI_ISSUE_BRANCH` | AI module PR branch | `3512345-fix` |

### System Variables

| Variable | Description | Default |
|----------|-------------|---------|
| `DP_AI_MODULES` | Modules to try (filtered) | `ai_provider_litellm,ai_search,ai_agents` |
| `DP_REBUILD` | Force clean rebuild | `1` (yes) or `0` (no) |

## Testing the Scripts

Run the test suite:

```bash
# Install BATS (first time only)
npm install

# Run all tests
npm test

# Run specific test suites
npm run test:unit          # Helper function tests
npm run test:integration   # Integration tests
npm run test:verbose       # Verbose output
```

### Test Coverage

**Unit Tests** (`tests/clone_ai_modules.bats`):
- ✓ Version constraint parsing (^2.0 → 2.0.x)
- ✓ Compatibility checking (ai_search vs AI 1.2.x)
- ✓ AI dependency extraction from composer.json

**Integration Tests** (`tests/integration.bats`):
- ✓ Auto-detect AI version from test module
- ✓ Validate explicit version conflicts
- ✓ Compatibility filtering logic
- ✓ Module inclusion/exclusion decisions

**Version Detection Tests** (`tests/fallback_setup.bats`):
- ✓ CMS/Core version to AI version mapping
- ✓ Explicit vs auto-detect tracking
- ✓ Install profile selection

## Development Workflow

### 1. Start Testing

```bash
ddev restart
```

### 2. Access the Site

- **URL**: https://drupalpod-ai-qa.ddev.site
- **Admin**: `admin` / `admin`

### 3. Work with Git Repos

All modules are in `repos/` as git submodules:

```bash
# SSH into container
ddev ssh

# Navigate to module
cd repos/ai_search

# Check branch
git status

# Make changes
vim src/Plugin/Search/SearchApiSearch.php

# Commit
git add .
git commit -m "Fix search bug"

# Changes are immediately active in web/modules/contrib/ai_search (symlinked)!
```

### 4. Switch PR Branches

```bash
# Edit .ddev/config.drupal.yaml
# Change DP_TEST_MODULE_ISSUE_BRANCH

# Restart
ddev restart
```

### 5. Clean Rebuild

```bash
# In .ddev/config.drupal.yaml:
# - DP_REBUILD=1

ddev restart
```

## Compatibility Matrix

| AI Version | ai_search | ai_provider_litellm | ai_agents |
|------------|-----------|---------------------|-----------|
| 1.0.x      | ✗ Skip    | ✗ Skip              | ✗ Skip    |
| 1.2.x      | ✗ Skip    | ✓ Include           | ✓ Include |
| 2.0.x      | ✓ Include | ✗ Skip              | ✗ Skip    |

**Note**: The system automatically filters modules based on their `composer.json` requirements.

## Troubleshooting

### Issue: Version Conflict Error

```
❌ ERROR: Version Conflict
Test module 'ai_search' requires AI 2.0.x
But you explicitly configured DP_AI_MODULE_VERSION=1.2.x
```

**Fix**: Remove `DP_AI_MODULE_VERSION` to auto-detect, or change to `2.0.x`

### Issue: Module Skipped

```
⚠️  Incompatible: ai_search requires AI ^2.0, but we have AI 1.2.x
✗ Skipping ai_search from composer (incompatible, but cloned for inspection)
```

**This is normal** - the module is incompatible and was correctly skipped.

### Issue: Drupal Not Installing

Check logs:

```bash
ddev ssh
cat logs/init-*.log
```

### Issue: Module Not Found

```bash
ddev ssh
ls -la repos/
```

### Issue: Wrong Branch

```bash
ddev ssh
cd repos/ai
git status
git branch -a
```

## Advanced Usage

### Test Against Drupal Core (Not CMS)

```yaml
# .ddev/config.yaml (system config)
- DP_STARTER_TEMPLATE=core
- DP_VERSION=11.x

# .ddev/config.drupal.yaml
- DP_TEST_MODULE=ai_search
```

Result: Lean setup without full CMS distribution.

### Force Specific Versions

```yaml
- DP_AI_MODULE_VERSION=2.0.x       # Explicitly set
- DP_TEST_MODULE_VERSION=2.0.0     # Specific release
```

### Check What Gets Installed

```bash
ddev ssh
drush pm:list --status=enabled | grep ai
```

## Contributing

### Running Tests Before Commit

```bash
npm test
```

All tests must pass before committing changes to the setup scripts.

### Adding New Tests

Add to `tests/integration.bats`:

```bash
@test "Your test description" {
    export DP_TEST_MODULE="ai_new_module"

    # Test logic here

    [ "$result" = "expected" ]
}
```

## Questions?

- Check `.ddev/config.drupal.yaml` for configuration examples
- Run `npm test` to verify setup logic
- Check logs in `logs/` directory
- Review scripts in `.devpanel/` for implementation details
