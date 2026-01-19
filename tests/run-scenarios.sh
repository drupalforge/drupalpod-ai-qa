#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Runner for AI Module Resolution Scenarios
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
SCENARIOS_FILE="${1:-$SCRIPT_DIR/scenarios.json}"

if [ ! -f "$SCENARIOS_FILE" ]; then
    echo "ERROR: Scenarios file not found: $SCENARIOS_FILE"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "ERROR: 'jq' is required to run tests"
    exit 1
fi

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

TOTAL_TESTS=0
PASSED_TESTS=0
FAILED_TESTS=0

run_scenario() {
    local scenario_json=$1
    local index=$2

    TOTAL_TESTS=$((TOTAL_TESTS + 1))

    # Parse scenario
    local name=$(echo "$scenario_json" | jq -r '.name')
    local description=$(echo "$scenario_json" | jq -r '.description')
    local should_succeed=$(echo "$scenario_json" | jq -r '.expect.should_succeed')

    echo ""
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${BLUE}Test $index: $name${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo "$description"
    echo ""

    # Set up environment
    export DP_STARTER_TEMPLATE=$(echo "$scenario_json" | jq -r '.env.DP_STARTER_TEMPLATE // "cms"')
    export DP_VERSION=$(echo "$scenario_json" | jq -r '.env.DP_VERSION // ""')
    export DP_AI_MODULE=$(echo "$scenario_json" | jq -r '.env.DP_AI_MODULE // "ai"')
    export DP_AI_MODULE_VERSION=$(echo "$scenario_json" | jq -r '.env.DP_AI_MODULE_VERSION // ""')
    export DP_AI_ISSUE_FORK=$(echo "$scenario_json" | jq -r '.env.DP_AI_ISSUE_FORK // ""')
    export DP_AI_ISSUE_BRANCH=$(echo "$scenario_json" | jq -r '.env.DP_AI_ISSUE_BRANCH // ""')
    export DP_TEST_MODULE=$(echo "$scenario_json" | jq -r '.env.DP_TEST_MODULE // ""')
    export DP_TEST_MODULE_VERSION=$(echo "$scenario_json" | jq -r '.env.DP_TEST_MODULE_VERSION // ""')
    export DP_AI_MODULES=$(echo "$scenario_json" | jq -r '.env.DP_AI_MODULES // ""')

    # Create test-specific log directory
    TEST_LOG_DIR="$PROJECT_ROOT/logs/test-$index"
    mkdir -p "$TEST_LOG_DIR"
    export DP_AI_RESOLVE_PLAN="$TEST_LOG_DIR/ai-manifest.json"

    echo "Environment:"
    echo "  DP_STARTER_TEMPLATE: $DP_STARTER_TEMPLATE"
    echo "  DP_VERSION: $DP_VERSION"
    echo "  DP_AI_MODULE: $DP_AI_MODULE"
    echo "  DP_AI_MODULE_VERSION: $DP_AI_MODULE_VERSION"
    [ -n "$DP_TEST_MODULE" ] && echo "  DP_TEST_MODULE: $DP_TEST_MODULE"
    [ -n "$DP_TEST_MODULE_VERSION" ] && echo "  DP_TEST_MODULE_VERSION: $DP_TEST_MODULE_VERSION"
    [ -n "$DP_AI_MODULES" ] && echo "  DP_AI_MODULES: $DP_AI_MODULES"
    echo ""

    # Run resolution script
    echo "Running resolve_modules.sh..."
    if bash "$PROJECT_ROOT/scripts/resolve_modules.sh" > "$TEST_LOG_DIR/output.log" 2>&1; then
        ACTUAL_SUCCESS=true
    else
        ACTUAL_SUCCESS=false
    fi

    # Check if plan file was created
    if [ -f "$DP_AI_RESOLVE_PLAN" ]; then
        echo "Resolution plan created:"
        cat "$DP_AI_RESOLVE_PLAN" | jq '.'
    else
        echo "No resolution plan created (script failed)"
    fi

    echo ""
    echo "Validation:"

    # Validate outcome
    local test_passed=true

    # Check success/failure expectation
    if [ "$should_succeed" = "true" ] && [ "$ACTUAL_SUCCESS" = "false" ]; then
        echo -e "  ${RED}✗ Expected success but got failure${NC}"
        test_passed=false
    elif [ "$should_succeed" = "false" ] && [ "$ACTUAL_SUCCESS" = "true" ]; then
        echo -e "  ${RED}✗ Expected failure but got success${NC}"
        test_passed=false
    else
        echo -e "  ${GREEN}✓ Success/failure expectation met${NC}"
    fi

    # If expected to succeed, validate the plan
    if [ "$should_succeed" = "true" ] && [ "$ACTUAL_SUCCESS" = "true" ] && [ -f "$DP_AI_RESOLVE_PLAN" ]; then

        # Check resolved modules
        local expected_modules=$(echo "$scenario_json" | jq -r '.expect.modules_resolved[]? // empty')
        if [ -n "$expected_modules" ]; then
            while IFS= read -r module; do
                if jq -e ".packages[] | select(.name==\"drupal/$module\")" "$DP_AI_RESOLVE_PLAN" > /dev/null; then
                    echo -e "  ${GREEN}✓ Module resolved: $module${NC}"
                else
                    echo -e "  ${RED}✗ Module NOT resolved: $module${NC}"
                    test_passed=false
                fi
            done <<< "$expected_modules"
        fi

        # Check AI version pattern
        local ai_version_pattern=$(echo "$scenario_json" | jq -r '.expect.ai_version_pattern // ""')
        if [ -n "$ai_version_pattern" ]; then
            local actual_ai_version=$(jq -r ".packages[] | select(.name==\"drupal/$DP_AI_MODULE\") | .version" "$DP_AI_RESOLVE_PLAN")
            if echo "$actual_ai_version" | grep -E "$ai_version_pattern" > /dev/null; then
                echo -e "  ${GREEN}✓ AI version matches pattern: $actual_ai_version ~ $ai_version_pattern${NC}"
            else
                echo -e "  ${RED}✗ AI version does NOT match pattern: $actual_ai_version !~ $ai_version_pattern${NC}"
                test_passed=false
            fi
        fi

        # Check lenient mode (from output log)
        local expect_lenient=$(echo "$scenario_json" | jq -r '.expect.lenient_enabled // false')
        if [ "$expect_lenient" = "true" ]; then
            if grep -q "Enabling lenient mode" "$TEST_LOG_DIR/output.log"; then
                echo -e "  ${GREEN}✓ Lenient mode enabled${NC}"

                # Check lenient packages
                local expected_lenient=$(echo "$scenario_json" | jq -r '.expect.lenient_packages[]? // empty')
                if [ -n "$expected_lenient" ]; then
                    while IFS= read -r pkg; do
                        if grep -q "$pkg" "$TEST_LOG_DIR/output.log"; then
                            echo -e "  ${GREEN}✓ Lenient package: $pkg${NC}"
                        else
                            echo -e "  ${RED}✗ Lenient package NOT found: $pkg${NC}"
                            test_passed=false
                        fi
                    done <<< "$expected_lenient"
                fi
            else
                echo -e "  ${RED}✗ Lenient mode NOT enabled (expected)${NC}"
                test_passed=false
            fi
        fi

        # Check skipped modules
        local expected_skipped=$(echo "$scenario_json" | jq -r '.expect.modules_skipped[]? // empty')
        if [ -n "$expected_skipped" ]; then
            while IFS= read -r module; do
                if jq -e ".skipped_packages[] | select(. == \"drupal/$module\")" "$DP_AI_RESOLVE_PLAN" > /dev/null 2>&1; then
                    echo -e "  ${GREEN}✓ Module skipped: $module${NC}"
                else
                    echo -e "  ${RED}✗ Module NOT skipped: $module${NC}"
                    test_passed=false
                fi
            done <<< "$expected_skipped"
        fi
    fi

    # Update test counters
    if [ "$test_passed" = "true" ]; then
        PASSED_TESTS=$((PASSED_TESTS + 1))
        echo ""
        echo -e "${GREEN}✓ Test PASSED${NC}"
    else
        FAILED_TESTS=$((FAILED_TESTS + 1))
        echo ""
        echo -e "${RED}✗ Test FAILED${NC}"
        echo "See logs in: $TEST_LOG_DIR"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main test loop
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}AI Module Resolution Test Suite${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Scenarios file: $SCENARIOS_FILE"
echo ""

# Read and run each scenario
scenario_count=$(jq 'length' "$SCENARIOS_FILE")
echo "Found $scenario_count test scenarios"

for i in $(seq 0 $((scenario_count - 1))); do
    scenario_json=$(jq ".[$i]" "$SCENARIOS_FILE")
    run_scenario "$scenario_json" $((i + 1))
done

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Summary
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}Test Summary${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo "Total tests:  $TOTAL_TESTS"
echo -e "Passed:       ${GREEN}$PASSED_TESTS${NC}"
echo -e "Failed:       ${RED}$FAILED_TESTS${NC}"
echo ""

if [ $FAILED_TESTS -gt 0 ]; then
    echo -e "${RED}Some tests failed!${NC}"
    exit 1
else
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
fi
