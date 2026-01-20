#!/usr/bin/env bats

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Suite for fallback_setup.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
    export APP_ROOT="$(pwd)"

    # Unset all variables to test defaults
    unset DP_STARTER_TEMPLATE
    unset DP_VERSION
    unset DP_AI_MODULE
    unset DP_AI_MODULE_VERSION
    unset DP_TEST_MODULE
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Default Value Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "DP_STARTER_TEMPLATE defaults to 'cms'" {
    source scripts/fallback_setup.sh
    [ "$DP_STARTER_TEMPLATE" = "cms" ]
}

@test "DP_VERSION defaults to empty for CMS (latest stable)" {
    export DP_STARTER_TEMPLATE="cms"
    source scripts/fallback_setup.sh
    [ -z "$DP_VERSION" ]
}

@test "DP_VERSION defaults to empty for core (latest stable)" {
    export DP_STARTER_TEMPLATE="core"
    source scripts/fallback_setup.sh
    [ -z "$DP_VERSION" ]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI Version Behavior Tests (Dependency-Driven, No Hardcoded Defaults)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "AI version defaults to empty (auto-detect from test module)" {
    export DP_STARTER_TEMPLATE="cms"
    export DP_VERSION="2.0.x"
    source scripts/fallback_setup.sh
    [ -z "$DP_AI_MODULE_VERSION" ]
}

@test "AI version stays empty for CMS 1.x (no hardcoded defaults)" {
    export DP_STARTER_TEMPLATE="cms"
    export DP_VERSION="1.x"
    source scripts/fallback_setup.sh
    [ -z "$DP_AI_MODULE_VERSION" ]
}

@test "AI version stays empty for Core 11.x (dependency-driven)" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="11.x"
    source scripts/fallback_setup.sh
    [ -z "$DP_AI_MODULE_VERSION" ]
}

@test "AI version stays empty for Core 10.x (dependency-driven)" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="10.x"
    source scripts/fallback_setup.sh
    [ -z "$DP_AI_MODULE_VERSION" ]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
@test "Empty DP_AI_MODULE_VERSION stays empty (dependency-driven)" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="11.x"
    export DP_AI_MODULE_VERSION=""  # Empty string
    source scripts/fallback_setup.sh
    [ -z "$DP_AI_MODULE_VERSION" ]  # Stays empty
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Version Validation Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "No error for CMS template with core version (9.x) without validation" {
    export DP_STARTER_TEMPLATE="cms"
    export DP_VERSION="9.x"
    run source scripts/fallback_setup.sh
    [ "$status" -eq 0 ]
}

@test "No error for core template with CMS version (1.x) without validation" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="1.x"
    run source scripts/fallback_setup.sh
    [ "$status" -eq 0 ]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Install Profile Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "CMS uses empty install profile (auto-detect drupal_cms_installer)" {
    export DP_STARTER_TEMPLATE="cms"
    source scripts/fallback_setup.sh
    [ -z "$DP_INSTALL_PROFILE" ]
}

@test "Core uses 'standard' install profile" {
    export DP_STARTER_TEMPLATE="core"
    source scripts/fallback_setup.sh
    [ "$DP_INSTALL_PROFILE" = "standard" ]
}

@test "Custom install profile can be overridden" {
    export DP_STARTER_TEMPLATE="cms"
    export DP_INSTALL_PROFILE="minimal"
    source scripts/fallback_setup.sh
    [ "$DP_INSTALL_PROFILE" = "minimal" ]
}
