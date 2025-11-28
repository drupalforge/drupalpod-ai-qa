#!/usr/bin/env bats

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Suite for clone_ai_modules.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
    # Set up test environment
    export APP_ROOT="$(pwd)"
    export DP_AI_MODULE="ai"

    # Create test repos directory structure
    mkdir -p repos/ai
    mkdir -p repos/ai_search
    mkdir -p repos/ai_provider_litellm
    mkdir -p repos/ai_agents

    # Create mock composer.json files for testing
    cat > repos/ai/composer.json <<'EOF'
{
    "name": "drupal/ai",
    "require": {
        "php": ">=8.1"
    }
}
EOF

    cat > repos/ai_search/composer.json <<'EOF'
{
    "name": "drupal/ai_search",
    "require": {
        "drupal/ai": "^2.0"
    }
}
EOF

    cat > repos/ai_provider_litellm/composer.json <<'EOF'
{
    "name": "drupal/ai_provider_litellm",
    "require": {
        "drupal/ai": "^1.2"
    }
}
EOF

    cat > repos/ai_agents/composer.json <<'EOF'
{
    "name": "drupal/ai_agents",
    "require": {
        "drupal/ai": "^1.2"
    }
}
EOF

    # Source ONLY helper functions (not main execution logic)
    # Extract function definitions without running the script
    eval "$(sed -n '/^get_ai_dependencies()/,/^}/p' .devpanel/clone_ai_modules.sh)"
    eval "$(sed -n '/^get_compatible_version()/,/^}/p' .devpanel/clone_ai_modules.sh)"
    eval "$(sed -n '/^is_compatible_with_ai()/,/^}/p' .devpanel/clone_ai_modules.sh)"
}

teardown() {
    # Clean up test directories
    rm -rf repos/ai repos/ai_search repos/ai_provider_litellm repos/ai_agents
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Helper Function Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "get_compatible_version extracts AI requirement from ai_search" {
    result=$(get_compatible_version "repos/ai_search" "ai")
    [ "$result" = "2.0.x" ]
}

@test "get_compatible_version extracts AI requirement from ai_provider_litellm" {
    result=$(get_compatible_version "repos/ai_provider_litellm" "ai")
    [ "$result" = "1.2.x" ]
}

@test "get_compatible_version returns empty for missing dependency" {
    result=$(get_compatible_version "repos/ai_search" "nonexistent")
    [ -z "$result" ]
}

@test "is_compatible_with_ai: ai_provider_litellm compatible with AI 1.2.x" {
    run is_compatible_with_ai "repos/ai_provider_litellm" "1.2.x"
    [ "$status" -eq 0 ]
}

@test "is_compatible_with_ai: ai_search incompatible with AI 1.2.x" {
    run is_compatible_with_ai "repos/ai_search" "1.2.x"
    [ "$status" -eq 1 ]
}

@test "is_compatible_with_ai: ai_search compatible with AI 2.0.x" {
    run is_compatible_with_ai "repos/ai_search" "2.0.x"
    [ "$status" -eq 0 ]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Version Constraint Parsing Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "parse version constraint: ^2.0 → 2.0.x" {
    # Create directory first, then composer.json
    mkdir -p repos/test
    cat > repos/test/composer.json <<'EOF'
{
    "require": {
        "drupal/ai": "^2.0"
    }
}
EOF
    result=$(get_compatible_version "repos/test" "ai")
    [ "$result" = "2.0.x" ]
    rm -rf repos/test
}

@test "parse version constraint: ^1.2.0 → 1.2.x" {
    mkdir -p repos/test
    cat > repos/test/composer.json <<'EOF'
{
    "require": {
        "drupal/ai": "^1.2.0"
    }
}
EOF
    result=$(get_compatible_version "repos/test" "ai")
    [ "$result" = "1.2.x" ]
    rm -rf repos/test
}

@test "parse version constraint: ~1.2.0 → 1.2.x" {
    mkdir -p repos/test
    cat > repos/test/composer.json <<'EOF'
{
    "require": {
        "drupal/ai": "~1.2.0"
    }
}
EOF
    result=$(get_compatible_version "repos/test" "ai")
    [ "$result" = "1.2.x" ]
    rm -rf repos/test
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Edge Cases
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "is_compatible_with_ai: module without composer.json is compatible" {
    mkdir -p repos/test_no_composer
    run is_compatible_with_ai "repos/test_no_composer" "1.2.x"
    [ "$status" -eq 0 ]
    rm -rf repos/test_no_composer
}

@test "is_compatible_with_ai: module without AI dependency is compatible" {
    mkdir -p repos/test_no_ai_dep
    cat > repos/test_no_ai_dep/composer.json <<'EOF'
{
    "require": {
        "php": ">=8.1"
    }
}
EOF
    run is_compatible_with_ai "repos/test_no_ai_dep" "1.2.x"
    [ "$status" -eq 0 ]
    rm -rf repos/test_no_ai_dep
}

@test "get_compatible_version: handles missing composer.json gracefully" {
    mkdir -p repos/test_missing
    result=$(get_compatible_version "repos/test_missing" "ai")
    [ -z "$result" ]
    rm -rf repos/test_missing
}
