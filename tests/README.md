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
# Run all scenarios
./tests/run-scenarios.sh

# Run a custom scenarios file
./tests/run-scenarios.sh tests/scenarios.json
```

Each scenario can set env vars (like `DP_VERSION`, `DP_AI_MODULE_VERSION`)
and optional `DP_FORCE_DEPENDENCIES=1` to bypass CMS/core constraints.
`DP_AI_MODULES` is validated against a repo allowlist; unknown modules fail fast.
Cached Composer artifacts are stored under `logs/cache` to speed up repeats.
Remove `logs/cache` to start fresh.

Example scenario:
```json
{
  "name": "CMS 1.x with forced AI 2.0.x",
  "env": {
    "DP_STARTER_TEMPLATE": "cms",
    "DP_VERSION": "1.x",
    "DP_AI_MODULE_VERSION": "2.0.x",
    "DP_FORCE_DEPENDENCIES": "1"
  },
  "expect": {
    "should_succeed": true
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

Add to `.github/workflows/test.yml`:

```yaml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      - run: npm ci
      - run: npm test
```
