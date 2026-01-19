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
    {"name": "drupal/ai", "version": "2.0.0"},
    {"name": "drupal/ai_search", "version": "2.0.x-dev"},
    {"name": "drupal/ai_provider_litellm", "version": "1.2.1"},
    {"name": "drupal/other_module", "version": "1.0.0"}
  ]
}
JSON

    eval "$(sed -n '/^write_manifest_from_lock()/,/^}/p' "$PROJECT_ROOT/scripts/resolve_modules.sh")"
}

teardown() {
    rm -rf "$PROJECT_ROOT/logs"
}

@test "write_manifest_from_lock filters to requested packages" {
    requested='["drupal/ai","drupal/ai_search"]'
    skipped='[]'
    write_manifest_from_lock "$PROJECT_ROOT/logs/composer.lock" "$requested" "$skipped" "$PROJECT_ROOT/logs/ai-manifest.json" "cms" "1.2.0"

    run jq -r '.packages[].name' "$PROJECT_ROOT/logs/ai-manifest.json"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "drupal/ai" ]]
    [[ "$output" =~ "drupal/ai_search" ]]
    [[ ! "$output" =~ "drupal/ai_provider_litellm" ]]
}

@test "write_manifest_from_lock includes skipped packages" {
    requested='["drupal/ai","drupal/ai_search"]'
    skipped='["drupal/ai_agents"]'
    write_manifest_from_lock "$PROJECT_ROOT/logs/composer.lock" "$requested" "$skipped" "$PROJECT_ROOT/logs/ai-manifest.json" "cms" "1.2.0"

    result=$(jq -r '.skipped_packages[]' "$PROJECT_ROOT/logs/ai-manifest.json")
    [ "$result" = "drupal/ai_agents" ]
}
