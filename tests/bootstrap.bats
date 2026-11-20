#!/usr/bin/env bats

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Suite for lib/bootstrap.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
    # Bootstrapping creates logs/ beside scripts/, so work on a copy to keep
    # the real logs/ untouched.
    TEST_PROJECT_ROOT="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT_ROOT"
    cp -R "$BATS_TEST_DIRNAME/../scripts" "$TEST_PROJECT_ROOT/scripts"
    TEST_SCRIPT_DIR="$TEST_PROJECT_ROOT/scripts"

    unset COMMON_BOOTSTRAPPED SCRIPT_DIR DP_AI_MODULE DP_MODULE_MANIFEST
    unset APP_ROOT COMPOSER_ROOT WEB_ROOT DP_APP_ROOT DP_COMPOSER_ROOT DP_WEB_ROOT
}

# Bootstraps in a parent shell, as init.sh does, then runs the given command.
run_after_bootstrap() {
    local command=$1
    run bash -c "export SCRIPT_DIR=\"\$1\"; source \"\$1/lib/bootstrap.sh\"; $command" _ "$TEST_SCRIPT_DIR"
}

@test "bootstrap does not export COMMON_BOOTSTRAPPED to child processes" {
    run_after_bootstrap 'bash -c "echo \${COMMON_BOOTSTRAPPED:-unset}"'
    [ "$status" -eq 0 ]
    [ "$output" = "unset" ]
}

@test "child bash script that sources bootstrap has the shared functions" {
    cat > "$TEST_SCRIPT_DIR/child_helper.sh" <<'BASH'
#!/usr/bin/env bash
set -eu -o pipefail
source "$SCRIPT_DIR/lib/bootstrap.sh"
strip_drupal_prefix "drupal/ai_search"
BASH

    run_after_bootstrap 'bash "$SCRIPT_DIR/child_helper.sh"'
    [ "$status" -eq 0 ]
    [ "$output" = "ai_search" ]
}

@test "enable_ai_modules.sh runs with bash after init has bootstrapped" {
    run_after_bootstrap 'bash "$SCRIPT_DIR/enable_ai_modules.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"command not found"* ]]
    [[ "$output" == *"No AI module configured"* ]]
}

@test "write_build_info.sh runs with bash after init has bootstrapped" {
    run_after_bootstrap 'bash "$SCRIPT_DIR/write_build_info.sh"'
    [ "$status" -eq 0 ]
    [[ "$output" != *"command not found"* ]]
    [[ "$output" == *"Module manifest not found"* ]]
}
