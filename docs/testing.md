# Setup Script Tests

Test suite for `scripts/*.sh` scripts using [bats](https://github.com/bats-core/bats-core).

**Tests verify logic and decisions, not actual execution** - no repos are cloned, no composer is run!
`jq` is required for plan parsing tests.

## Installation

```bash
# Install dependencies
npm install

# Or install bats manually
brew install bats-core  # macOS
sudo apt-get install bats  # Ubuntu/Debian
```

## Running Tests

```bash
# Run all tests
npm test

# Unit tests only (helper functions)
npm run test:unit

# Integration tests only (decision logic)
npm run test:integration

# Verbose output
npm run test:verbose

# Run specific test file
bats tests/integration.bats
```

## Scenario Runner (Composer Resolution)

The scenario runner executes `scripts/resolve_modules.sh` against a JSON list.
It uses Composer and writes plans to `logs/test-{N}/ai-manifest.json`.

```bash
# Run all scenarios (default compatibility tests)
./tests/run-scenarios.sh

# Run Drupal resolution mode tests
./tests/run-scenarios.sh tests/scenarios-drupal-resolution.json

# Run with custom scenarios file
./tests/run-scenarios.sh tests/custom-scenarios.json
```

### Scenario Files

- **`scenarios.json`** - Compatibility test suite covering all combinations of CMS/Core versions, AI module versions, test modules, optional modules, lenient mode, and performance flags (DP_NO_DEV)
- **`scenarios-drupal-resolution.json`** - Resolution mode validation suite that tests auto-detection logic, verifies which resolution mode (1-4) is selected, and validates which CMS/Core version gets resolved

Each scenario can set env vars (like `DP_VERSION`, `DP_AI_MODULE_VERSION`, `DP_NO_DEV`)
and optional `DP_FORCE_DEPENDENCIES=1` to relax `drupal/ai` constraints
via the local Composer plugin.
`DP_AI_MODULES` is validated against a repo allowlist; unknown modules fail fast.

### Resolution Modes

Tests in `scenarios-drupal-resolution.json` validate which mode is selected:

- **MODE_AUTO (3)**: Neither CMS nor AI pinned - full auto-detection
- **MODE_AI_PINNED (1)**: AI/test module pinned, CMS auto-detects
- **MODE_CMS_PINNED (2)**: CMS pinned, AI auto-detects
- **MODE_AI_AND_CMS_PINNED (4)**: Both pinned - path repos eligible for conflict resolution

Example compatibility scenario:
```json
{
  "name": "CMS 1.x with forced AI 2.0.x",
  "description": "Force AI 2.0.x on CMS with dependency overrides",
  "env": {
    "DP_STARTER_TEMPLATE": "cms",
    "DP_VERSION": "1.x",
    "DP_AI_MODULE": "ai",
    "DP_AI_MODULE_VERSION": "2.0.x",
    "DP_NO_DEV": "1",
    "DP_FORCE_DEPENDENCIES": "1"
  },
  "expect": {
    "should_succeed": true,
    "lenient_enabled": true,
    "ai_version_pattern": "(^dev-2\\.0\\.x$|^2\\.0\\.x-dev$)"
  }
}
```

Example resolution mode scenario:
```json
{
  "name": "MODE_CMS_PINNED (2): CMS 1.x forces AI 1.x",
  "description": "CMS pinned to 1.x, AI should auto-detect to 1.x",
  "env": {
    "DP_STARTER_TEMPLATE": "cms",
    "DP_VERSION": "1.x",
    "DP_AI_MODULE": "ai",
    "DP_AI_MODULE_VERSION": ""
  },
  "expect": {
    "should_succeed": true,
    "resolution_mode": 2,
    "drupal_version_pattern": "^1\\.",
    "ai_version_pattern": "^1\\."
  }
}
```

## Test Structure

### Unit Tests (Helper Functions)

**`fallback_setup.bats`** - Tests for `scripts/fallback_setup.sh`
- ✓ Default value detection
- ✓ AI version auto-detection from CMS/Core version
- ✓ Version validation (CMS vs Core)

**`clone_modules.bats`** - Tests for `scripts/clone_modules.sh`
- ✓ Composer version → git branch/tag normalization
- ✓ Resolution plan parsing

**`resolve_modules.bats`** - Tests for `scripts/resolve_modules.sh`
- ✓ Plan generation from `composer.lock`
- ✓ Skipped package reporting

### Integration Tests (Decision Logic)

**`integration.bats`** - Tests the **decisions** the scripts make (without actually cloning or installing):

**Use Case: Resolution Plan**
- ✓ Plan includes only requested packages from `composer.lock`
- ✓ Plan captures allow-incompatible flag

## Writing New Tests

```bash
@test "descriptive test name" {
    # Setup
    export SOME_VAR="value"

    # Run command
    run some_command

    # Assertions
    [ "$status" -eq 0 ]           # Exit code 0
    [[ "$output" =~ "pattern" ]]  # Output matches pattern
    [ "$result" = "expected" ]    # Exact match
}
```

## CI Integration

GitLab CI workflow: `.gitlab-ci.yml`

Three-layer pipeline:

1. **Layer 1 (smoke)**: `bats` unit tests + `template-version-smoke` (6 scenarios in parallel)
2. **Layer 2 (resolution)**: `drupal-resolution-matrix` (14 resolution mode scenarios in parallel)
3. **Layer 3 (extended)**: `scenario-matrix` (30-way parallel compatibility suite)

Jobs:
- `bats` - Unit tests (`npm ci` + `npm test`)
- `template-version-smoke` - 6-way parallel matrix using `tests/scenarios-template-version.json`
- `drupal-resolution-matrix` - 14-way parallel matrix using `tests/scenarios-drupal-resolution.json`
- `scenario-matrix` - 30-way parallel matrix using `tests/scenarios.json`
