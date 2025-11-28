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
    unset DP_AI_MODULE_VERSION_EXPLICIT
    unset DP_TEST_MODULE
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Default Value Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "DP_STARTER_TEMPLATE defaults to 'cms'" {
    source .devpanel/fallback_setup.sh
    [ "$DP_STARTER_TEMPLATE" = "cms" ]
}

@test "DP_VERSION defaults to '1.x' for CMS" {
    export DP_STARTER_TEMPLATE="cms"
    source .devpanel/fallback_setup.sh
    [ "$DP_VERSION" = "1.x" ]
}

@test "DP_VERSION defaults to '11.2.8' for core" {
    export DP_STARTER_TEMPLATE="core"
    source .devpanel/fallback_setup.sh
    [ "$DP_VERSION" = "11.2.8" ]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI Version Auto-Detection Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "CMS 2.x → AI 1.2.x" {
    export DP_STARTER_TEMPLATE="cms"
    export DP_VERSION="2.0.x"
    source .devpanel/fallback_setup.sh
    [ "$DP_AI_MODULE_VERSION" = "1.2.x" ]
}

@test "CMS 1.x → AI 1.0.x" {
    export DP_STARTER_TEMPLATE="cms"
    export DP_VERSION="1.x"
    source .devpanel/fallback_setup.sh
    [ "$DP_AI_MODULE_VERSION" = "1.0.x" ]
}

@test "Core 11.x → AI 1.2.x" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="11.x"
    source .devpanel/fallback_setup.sh
    [ "$DP_AI_MODULE_VERSION" = "1.2.x" ]
}

@test "Core 10.x → AI 1.0.x" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="10.x"
    source .devpanel/fallback_setup.sh
    [ "$DP_AI_MODULE_VERSION" = "1.0.x" ]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Explicit Version Tracking Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "DP_AI_MODULE_VERSION_EXPLICIT=no when version is auto-detected" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="11.x"
    # Don't set DP_AI_MODULE_VERSION - let it auto-detect
    source .devpanel/fallback_setup.sh
    [ "$DP_AI_MODULE_VERSION_EXPLICIT" = "no" ]
}

@test "DP_AI_MODULE_VERSION_EXPLICIT=yes when version is explicitly set" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="11.x"
    export DP_AI_MODULE_VERSION="2.0.x"  # Explicitly set
    source .devpanel/fallback_setup.sh
    [ "$DP_AI_MODULE_VERSION_EXPLICIT" = "yes" ]
    [ "$DP_AI_MODULE_VERSION" = "2.0.x" ]
}

@test "Empty DP_AI_MODULE_VERSION is treated as unset (auto-detect)" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="11.x"
    export DP_AI_MODULE_VERSION=""  # Empty string
    source .devpanel/fallback_setup.sh
    [ "$DP_AI_MODULE_VERSION_EXPLICIT" = "no" ]
    [ "$DP_AI_MODULE_VERSION" = "1.2.x" ]  # Auto-detected
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Version Validation Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "Error: CMS template with core version (9.x)" {
    export DP_STARTER_TEMPLATE="cms"
    export DP_VERSION="9.x"
    run source .devpanel/fallback_setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "looks like a Drupal core version" ]]
}

@test "Error: Core template with CMS version (1.x)" {
    export DP_STARTER_TEMPLATE="core"
    export DP_VERSION="1.x"
    run source .devpanel/fallback_setup.sh
    [ "$status" -eq 1 ]
    [[ "$output" =~ "looks like a CMS version" ]]
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Install Profile Tests
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

@test "CMS uses empty install profile (auto-detect drupal_cms_installer)" {
    export DP_STARTER_TEMPLATE="cms"
    source .devpanel/fallback_setup.sh
    [ -z "$DP_INSTALL_PROFILE" ]
}

@test "Core uses 'standard' install profile" {
    export DP_STARTER_TEMPLATE="core"
    source .devpanel/fallback_setup.sh
    [ "$DP_INSTALL_PROFILE" = "standard" ]
}

@test "Custom install profile can be overridden" {
    export DP_STARTER_TEMPLATE="cms"
    export DP_INSTALL_PROFILE="minimal"
    source .devpanel/fallback_setup.sh
    [ "$DP_INSTALL_PROFILE" = "minimal" ]
}
