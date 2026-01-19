# AI Module Resolution Test Scenarios

This directory contains an automated test framework for validating AI module dependency resolution across different configurations.

## Quick Start

```bash
# Run all test scenarios
./tests/run-scenarios.sh

# Run a specific scenarios file
./tests/run-scenarios.sh tests/my-custom-scenarios.json
```

## Test Scenario Structure

Each test scenario in `scenarios.json` has this structure:

```json
{
  "name": "Short test name",
  "description": "Longer description of what's being tested",
  "env": {
    "DP_STARTER_TEMPLATE": "cms",
    "DP_VERSION": "1.x",
    "DP_AI_MODULE": "ai",
    "DP_AI_MODULE_VERSION": "",
    "DP_TEST_MODULE": "",
    "DP_TEST_MODULE_VERSION": "",
    "DP_AI_MODULES": "",
    "DP_AI_ISSUE_FORK": "",
    "DP_AI_ISSUE_BRANCH": ""
  },
  "expect": {
    "should_succeed": true,
    "lenient_enabled": false,
    "lenient_packages": [],
    "ai_version_pattern": "^1\\.",
    "modules_resolved": ["ai", "ai_provider_litellm"],
    "comment": "Optional notes about expected behavior"
  }
}
```

## Environment Variables

### Core Settings
- **DP_STARTER_TEMPLATE**: `cms` or `core`
- **DP_VERSION**: Drupal version (e.g., `1.x`, `1.2.0`, `11.x`, empty for latest)

### AI Module Settings
- **DP_AI_MODULE**: Base AI module name (usually `ai`)
- **DP_AI_MODULE_VERSION**:
  - Empty = auto-detect from dependencies (recommended)
  - Explicit = force version, enables lenient mode for CMS/core constraints
- **DP_AI_ISSUE_FORK**: Fork ID for testing AI PRs
- **DP_AI_ISSUE_BRANCH**: Branch name for testing AI PRs

### Test Module Settings
- **DP_TEST_MODULE**: Module being tested (e.g., `ai_search`)
- **DP_TEST_MODULE_VERSION**:
  - Empty = auto-detect from dev branch
  - Explicit = force version
- **DP_TEST_MODULE_ISSUE_FORK**: Fork ID for testing module PRs
- **DP_TEST_MODULE_ISSUE_BRANCH**: Branch for testing module PRs

### Additional Modules
- **DP_AI_MODULES**: Comma-separated list of extra AI modules (e.g., `ai_search,ai_agents`)

## Expectations

### Basic Checks
- **should_succeed**: `true` if resolution should succeed, `false` if it should fail
- **modules_resolved**: Array of module names that should be in the resolution plan

### Version Validation
- **ai_version_pattern**: Regex pattern to match the resolved AI version (e.g., `^2\\..*-dev$`)

### Lenient Mode Validation
- **lenient_enabled**: `true` if lenient mode should be active
- **lenient_packages**: Array of packages that should be in the lenient list

## Example Scenarios

### Test Latest AI with CMS
```json
{
  "name": "CMS 1.x with latest AI",
  "env": {
    "DP_STARTER_TEMPLATE": "cms",
    "DP_VERSION": "1.x",
    "DP_AI_MODULE": "ai",
    "DP_AI_MODULE_VERSION": ""
  },
  "expect": {
    "should_succeed": true,
    "modules_resolved": ["ai", "ai_provider_litellm"]
  }
}
```

### Force AI 2.x on CMS 1.x
```json
{
  "name": "CMS 1.x with AI 2.x override",
  "env": {
    "DP_STARTER_TEMPLATE": "cms",
    "DP_VERSION": "1.x",
    "DP_AI_MODULE": "ai",
    "DP_AI_MODULE_VERSION": "2.x"
  },
  "expect": {
    "should_succeed": true,
    "lenient_enabled": true,
    "lenient_packages": ["drupal/ai"],
    "ai_version_pattern": "^2\\..*-dev$"
  }
}
```

### Test ai_search Compatibility
```json
{
  "name": "Test ai_search auto-detection",
  "env": {
    "DP_STARTER_TEMPLATE": "cms",
    "DP_VERSION": "1.x",
    "DP_AI_MODULE": "ai",
    "DP_AI_MODULE_VERSION": "",
    "DP_TEST_MODULE": "ai_search",
    "DP_TEST_MODULE_VERSION": ""
  },
  "expect": {
    "should_succeed": true,
    "modules_resolved": ["ai", "ai_provider_litellm", "ai_search"]
  }
}
```

### Test Multiple AI Modules
```json
{
  "name": "Multiple AI modules compatibility",
  "env": {
    "DP_STARTER_TEMPLATE": "cms",
    "DP_VERSION": "1.x",
    "DP_AI_MODULE": "ai",
    "DP_AI_MODULE_VERSION": "",
    "DP_AI_MODULES": "ai_search,ai_agents,ai_automator"
  },
  "expect": {
    "should_succeed": true,
    "modules_resolved": ["ai", "ai_provider_litellm", "ai_search", "ai_agents", "ai_automator"]
  }
}
```

## Test Output

Each test creates a log directory in `logs/test-{N}/` containing:
- `ai-manifest.json`: The generated resolution plan
- `output.log`: Console output from the resolution script

## Understanding Lenient Mode

Lenient mode uses `mglaman/composer-drupal-lenient` to bypass version constraints. It automatically enables when:

1. **AI version is explicit**: Bypasses CMS/core AI version constraints
2. **Both test module AND AI versions explicit**: Allows testing incompatible combinations

### When Lenient is NOT Used
- AI extra modules (like `ai_search`, `ai_agents`) **must** be compatible with the base AI version
- These dependencies are resolved properly through Composer - incompatibility is a real error

## Adding New Test Scenarios

1. Edit `scenarios.json`
2. Add your new scenario object to the array
3. Run the test suite: `./tests/run-scenarios.sh`
4. Check logs in `logs/test-{N}/` if tests fail

## CI/CD Integration

The test script exits with:
- `0` if all tests pass
- `1` if any test fails

This makes it easy to integrate into CI pipelines:

```bash
# In GitHub Actions, DDEV, etc.
./tests/run-scenarios.sh || exit 1
```
