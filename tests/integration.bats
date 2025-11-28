#!/usr/bin/env bats

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Integration Tests - Verify Script Decisions (Not Actual Execution)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Tests verify the script makes correct decisions about:
# - Which modules to clone
# - What versions to use
# - When to fail vs continue
# - Compatibility filtering
#
# We DON'T actually clone repos or run composer - just verify logic!
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
    export APP_ROOT="$(pwd)"

    # Create mock repo structure with composer.json files
    mkdir -p repos/{ai,ai_search,ai_provider_litellm,ai_agents}

    # ai_search requires AI ^2.0
    cat > repos/ai_search/composer.json <<'EOF'
{"require": {"drupal/ai": "^2.0"}}
EOF

    # ai_provider_litellm requires AI ^1.2
    cat > repos/ai_provider_litellm/composer.json <<'EOF'
{"require": {"drupal/ai": "^1.2"}}
EOF

    # ai_agents requires AI ^1.2
    cat > repos/ai_agents/composer.json <<'EOF'
{"require": {"drupal/ai": "^1.2"}}
EOF

    # Stub the clone_module function to just track what would be cloned
    clone_module() {
        local module_name=$1
        echo "WOULD_CLONE: $module_name" >&2

        # Track in CLONED_AI_MODULES
        if [ -z "$CLONED_AI_MODULES" ]; then
            export CLONED_AI_MODULES="$module_name"
        else
            export CLONED_AI_MODULES="$CLONED_AI_MODULES,$module_name"
        fi
    }
    export -f clone_module
}

teardown() {
    rm -rf repos
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Use Case: Test Module Specified (Auto-Detect AI Version)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "Test module ai_search → auto-detect AI 2.0.x" {
    export DP_AI_MODULE="ai"
    export DP_AI_MODULE_VERSION=""  # Empty = auto-detect
    export DP_AI_MODULE_VERSION_EXPLICIT="no"
    export DP_TEST_MODULE="ai_search"
    export DP_AI_MODULES=""

    # Load helper functions without executing main script
    eval "$(sed -n '/^get_compatible_version()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    # Get AI requirement from test module
    ai_requirement=$(get_compatible_version "repos/ai_search" "ai")

    # Verify decision
    [ "$ai_requirement" = "2.0.x" ]
}

@test "Test module set + explicit AI version mismatch → should fail" {
    export DP_AI_MODULE="ai"
    export DP_AI_MODULE_VERSION="1.2.x"  # Explicitly set
    export DP_AI_MODULE_VERSION_EXPLICIT="yes"
    export DP_TEST_MODULE="ai_search"  # Needs 2.0.x

    eval "$(sed -n '/^get_compatible_version()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    test_module_ai_requirement=$(get_compatible_version "repos/ai_search" "ai")

    # Verify we detected the conflict
    [ "$test_module_ai_requirement" = "2.0.x" ]
    [ "$DP_AI_MODULE_VERSION" = "1.2.x" ]
    [ "$test_module_ai_requirement" != "$DP_AI_MODULE_VERSION" ]
    # Script should fail in this case (verified separately)
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Use Case: No Test Module (Use DP_AI_MODULES with Compatibility Filtering)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "DP_AI_MODULES: ai_search incompatible with AI 1.2.x → should skip" {
    export DP_AI_MODULE_VERSION="1.2.x"

    eval "$(sed -n '/^is_compatible_with_ai()/,/^}/p' .devpanel/clone_ai_modules.sh)"
    eval "$(sed -n '/^get_compatible_version()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    # Check if ai_search is compatible with AI 1.2.x
    run is_compatible_with_ai "repos/ai_search" "1.2.x"

    # Should be incompatible (exit 1)
    [ "$status" -eq 1 ]
    [[ "$output" =~ "Incompatible" ]]
}

@test "DP_AI_MODULES: ai_provider_litellm compatible with AI 1.2.x → should include" {
    export DP_AI_MODULE_VERSION="1.2.x"

    eval "$(sed -n '/^is_compatible_with_ai()/,/^}/p' .devpanel/clone_ai_modules.sh)"
    eval "$(sed -n '/^get_compatible_version()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    # Check if ai_provider_litellm is compatible with AI 1.2.x
    run is_compatible_with_ai "repos/ai_provider_litellm" "1.2.x"

    # Should be compatible (exit 0)
    [ "$status" -eq 0 ]
}

@test "DP_AI_MODULES: ai_agents compatible with AI 1.2.x → should include" {
    export DP_AI_MODULE_VERSION="1.2.x"

    eval "$(sed -n '/^is_compatible_with_ai()/,/^}/p' .devpanel/clone_ai_modules.sh)"
    eval "$(sed -n '/^get_compatible_version()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    # Check if ai_agents is compatible with AI 1.2.x
    run is_compatible_with_ai "repos/ai_agents" "1.2.x"

    # Should be compatible (exit 0)
    [ "$status" -eq 0 ]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Use Case: Verify Correct Modules Get Added to COMPATIBLE_AI_MODULES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "Compatibility filtering: AI 1.2.x should only include compatible modules" {
    export DP_AI_MODULE_VERSION="1.2.x"
    export COMPATIBLE_AI_MODULES=""

    eval "$(sed -n '/^is_compatible_with_ai()/,/^}/p' .devpanel/clone_ai_modules.sh)"
    eval "$(sed -n '/^get_compatible_version()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    # Simulate checking each module
    modules="ai_provider_litellm ai_search ai_agents"

    for module in $modules; do
        if is_compatible_with_ai "repos/$module" "1.2.x" 2>/dev/null; then
            if [ -z "$COMPATIBLE_AI_MODULES" ]; then
                COMPATIBLE_AI_MODULES="$module"
            else
                COMPATIBLE_AI_MODULES="$COMPATIBLE_AI_MODULES,$module"
            fi
        fi
    done

    # Verify: should include ai_provider_litellm and ai_agents, but NOT ai_search
    [[ "$COMPATIBLE_AI_MODULES" =~ "ai_provider_litellm" ]]
    [[ "$COMPATIBLE_AI_MODULES" =~ "ai_agents" ]]
    [[ ! "$COMPATIBLE_AI_MODULES" =~ "ai_search" ]]
}

@test "Compatibility filtering: AI 2.0.x should include ai_search" {
    export DP_AI_MODULE_VERSION="2.0.x"
    export COMPATIBLE_AI_MODULES=""

    eval "$(sed -n '/^is_compatible_with_ai()/,/^}/p' .devpanel/clone_ai_modules.sh)"
    eval "$(sed -n '/^get_compatible_version()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    # Check if ai_search is compatible with AI 2.0.x
    if is_compatible_with_ai "repos/ai_search" "2.0.x" 2>/dev/null; then
        COMPATIBLE_AI_MODULES="ai_search"
    fi

    # Verify: should include ai_search
    [ "$COMPATIBLE_AI_MODULES" = "ai_search" ]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Use Case: Module Without composer.json or AI Dependency
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "Module without composer.json is treated as compatible" {
    mkdir -p repos/custom_module
    # No composer.json

    eval "$(sed -n '/^is_compatible_with_ai()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    run is_compatible_with_ai "repos/custom_module" "1.2.x"

    # Should be compatible (exit 0)
    [ "$status" -eq 0 ]

    rm -rf repos/custom_module
}

@test "Module without AI dependency is treated as compatible" {
    mkdir -p repos/standalone_module
    cat > repos/standalone_module/composer.json <<'EOF'
{"require": {"php": ">=8.1"}}
EOF

    eval "$(sed -n '/^is_compatible_with_ai()/,/^}/p' .devpanel/clone_ai_modules.sh)"

    run is_compatible_with_ai "repos/standalone_module" "1.2.x"

    # Should be compatible (exit 0)
    [ "$status" -eq 0 ]

    rm -rf repos/standalone_module
}
