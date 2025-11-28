# DevPanel Shell Script Tests

Test suite for `.devpanel/*.sh` scripts using [bats](https://github.com/bats-core/bats-core).

**Tests verify logic and decisions, not actual execution** - no repos are cloned, no composer is run!

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

## Test Structure

### Unit Tests (Helper Functions)

**`fallback_setup.bats`** - Tests for `.devpanel/fallback_setup.sh`
- ✓ Default value detection
- ✓ AI version auto-detection from CMS/Core version
- ✓ Explicit version tracking (DP_AI_MODULE_VERSION_EXPLICIT flag)
- ✓ Version validation (CMS vs Core)

**`clone_ai_modules.bats`** - Tests for `.devpanel/clone_ai_modules.sh`
- ✓ Helper function tests (`get_compatible_version`, `is_compatible_with_ai`)
- ✓ Version constraint parsing (^2.0 → 2.0.x, ~1.2.0 → 1.2.x)
- ✓ Compatibility checking
- ✓ Edge cases (missing composer.json, no AI dependency)

### Integration Tests (Decision Logic)

**`integration.bats`** - Tests the **decisions** the scripts make (without actually cloning or installing):

**Use Case: Test Module Specified**
- ✓ ai_search with empty AI version → auto-detect AI 2.0.x
- ✓ ai_search with explicit AI 1.2.x → detect conflict (should fail)

**Use Case: DP_AI_MODULES with Compatibility Filtering**
- ✓ AI 1.2.x → ai_search incompatible (skip)
- ✓ AI 1.2.x → ai_provider_litellm compatible (include)
- ✓ AI 1.2.x → ai_agents compatible (include)
- ✓ AI 2.0.x → ai_search compatible (include)

**Use Case: Edge Cases**
- ✓ Module without composer.json → treat as compatible
- ✓ Module without AI dependency → treat as compatible

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
