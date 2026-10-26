#!/usr/bin/env bats

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Suite for resolve_modules.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    mkdir -p "$PROJECT_ROOT/logs"
    cat > "$PROJECT_ROOT/logs/composer.lock" <<'JSON'
{
  "packages": [
    {"name": "drupal/cms", "version": "2.0.1"},
    {"name": "drupal/core-recommended", "version": "11.2.0"},
    {"name": "drupal/ai", "version": "2.0.0"},
    {"name": "drupal/ai_search", "version": "2.0.x-dev"},
    {"name": "drupal/ai_provider_litellm", "version": "1.2.1"},
    {"name": "drupal/other_module", "version": "1.0.0"}
  ]
}
JSON

    source "$PROJECT_ROOT/scripts/lib/common.sh"
    for function in write_manifest_from_lock contains_package add_optional_module collect_optional_modules; do
        eval "$(sed -n "/^${function}()/,/^}/p" "$PROJECT_ROOT/scripts/resolve_modules.sh")"
    done
    REQUIRED_PACKAGES=()
    OPTIONAL_PACKAGES=()
    OPTIONAL_CONSTRAINTS=()
    DP_AI_MODULE=ai
    DP_TEST_MODULE=""
    DP_TEST_MODULE_VERSION=""
}

teardown() {
    rm -rf "$PROJECT_ROOT/logs"
}

@test "write_manifest_from_lock filters to requested packages" {
    requested='["drupal/ai","drupal/ai_search"]'
    skipped='[]'
    write_manifest_from_lock "$PROJECT_ROOT/logs/composer.lock" "$requested" "$skipped" "$PROJECT_ROOT/logs/ai-manifest.json" "cms" "1.2.0" "drupal/cms" "1.2.x-dev"

    run jq -r '.packages[].name' "$PROJECT_ROOT/logs/ai-manifest.json"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "drupal/ai" ]]
    [[ "$output" =~ "drupal/ai_search" ]]
    [[ ! "$output" =~ "drupal/ai_provider_litellm" ]]
}

@test "write_manifest_from_lock includes skipped packages" {
    requested='["drupal/ai","drupal/ai_search"]'
    skipped='["drupal/ai_agents"]'
    write_manifest_from_lock "$PROJECT_ROOT/logs/composer.lock" "$requested" "$skipped" "$PROJECT_ROOT/logs/ai-manifest.json" "cms" "1.2.0" "drupal/cms" "1.2.x-dev"

    result=$(jq -r '.skipped_packages[]' "$PROJECT_ROOT/logs/ai-manifest.json")
    [ "$result" = "drupal/ai_agents" ]
}

@test "write_manifest_from_lock records resolved project package and version" {
    requested='["drupal/ai"]'
    skipped='[]'
    write_manifest_from_lock "$PROJECT_ROOT/logs/composer.lock" "$requested" "$skipped" "$PROJECT_ROOT/logs/ai-manifest.json" "cms" "2.x" "drupal/cms" "2.x-dev"

    project_package=$(jq -r '.resolved_project_package' "$PROJECT_ROOT/logs/ai-manifest.json")
    project_version=$(jq -r '.resolved_project_version' "$PROJECT_ROOT/logs/ai-manifest.json")

    [ "$project_package" = "drupal/cms" ]
    [ "$project_version" = "2.0.1" ]
}

@test "extra modules select a pinned or automatic provider without setting the startup test module" {
    for entry in "ai_provider_amazeeio:1.2.7" "ai_provider_amazeeio"; do
        OPTIONAL_PACKAGES=()
        OPTIONAL_CONSTRAINTS=()
        DP_EXTRA_MODULES=" ai_search, ,${entry},ai_agents "
        collect_optional_modules

        [ "${OPTIONAL_PACKAGES[*]}" = "drupal/ai_search drupal/ai_provider_amazeeio drupal/ai_agents" ]
        [ "${OPTIONAL_CONSTRAINTS[0]}" = "*" ]
        if [[ "$entry" == *:* ]]; then
            [ "${OPTIONAL_CONSTRAINTS[1]}" = "1.2.7" ]
        else
            [ "${OPTIONAL_CONSTRAINTS[1]}" = "*" ]
        fi
        [ "${OPTIONAL_CONSTRAINTS[2]}" = "*" ]
        [ -z "$DP_TEST_MODULE" ]
        [ -z "$DP_TEST_MODULE_VERSION" ]
    done
}

@test "extra module constraints do not override the module selected at startup" {
    DP_TEST_MODULE=ai_agents
    DP_TEST_MODULE_VERSION=1.0.0
    DP_EXTRA_MODULES="ai:^1,ai_agents:^2,ai_provider_amazeeio:>=1.0 <1.3,ai_provider_amazeeio:1.2.0"
    collect_optional_modules

    [ "${OPTIONAL_PACKAGES[*]}" = "drupal/ai_provider_amazeeio" ]
    [ "${OPTIONAL_CONSTRAINTS[*]}" = ">=1.0 <1.3" ]
    [ "$DP_TEST_MODULE" = "ai_agents" ]
    [ "$DP_TEST_MODULE_VERSION" = "1.0.0" ]
}

@test "extra modules reject invalid module names" {
    DP_EXTRA_MODULES="invalid/name:1.2.7"
    run collect_optional_modules

    [ "$status" -ne 0 ]
    [[ "$output" == *"Invalid module name"* ]]
}

@test "image workflow preinstalls the provider without baking in startup test variables" {
    workflow="$PROJECT_ROOT/.github/workflows/docker-publish-image.yml"
    run grep -E '^[[:space:]]+DP_TEST_MODULE(_VERSION)?:' "$workflow"
    [ "$status" -eq 1 ]
    grep -Fq 'ai_provider_amazeeio:1.2.7' "$workflow"
    grep -Fq 'ai_search,ai_agents,ai_provider_amazeeio,ai_image_alt_text' "$workflow"
    grep -Fq 'pm:list --type=module --status=enabled --field=name | grep -Fx ai_provider_amazeeio' "$workflow"
}
