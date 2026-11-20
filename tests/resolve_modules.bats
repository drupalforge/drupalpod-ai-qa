#!/usr/bin/env bats

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Suite for resolve_modules.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    LOCK_FIXTURE="$BATS_TEST_TMPDIR/composer.lock"
    MANIFEST_OUTPUT="$BATS_TEST_TMPDIR/ai-manifest.json"
    cat > "$LOCK_FIXTURE" <<'JSON'
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

    eval "$(sed -n '/^write_manifest_from_lock()/,/^}/p' "$PROJECT_ROOT/scripts/resolve_modules.sh")"
}

@test "write_manifest_from_lock filters to requested packages" {
    requested='["drupal/ai","drupal/ai_search"]'
    skipped='[]'
    write_manifest_from_lock "$LOCK_FIXTURE" "$requested" "$skipped" "$MANIFEST_OUTPUT" "cms" "1.2.0" "drupal/cms" "1.2.x-dev"

    run jq -r '.packages[].name' "$MANIFEST_OUTPUT"
    [ "$status" -eq 0 ]
    [[ "$output" =~ "drupal/ai" ]]
    [[ "$output" =~ "drupal/ai_search" ]]
    [[ ! "$output" =~ "drupal/ai_provider_litellm" ]]
}

@test "write_manifest_from_lock includes skipped packages" {
    requested='["drupal/ai","drupal/ai_search"]'
    skipped='["drupal/ai_agents"]'
    write_manifest_from_lock "$LOCK_FIXTURE" "$requested" "$skipped" "$MANIFEST_OUTPUT" "cms" "1.2.0" "drupal/cms" "1.2.x-dev"

    result=$(jq -r '.skipped_packages[]' "$MANIFEST_OUTPUT")
    [ "$result" = "drupal/ai_agents" ]
}

@test "write_manifest_from_lock records resolved project package and version" {
    requested='["drupal/ai"]'
    skipped='[]'
    write_manifest_from_lock "$LOCK_FIXTURE" "$requested" "$skipped" "$MANIFEST_OUTPUT" "cms" "2.x" "drupal/cms" "2.x-dev"

    project_package=$(jq -r '.resolved_project_package' "$MANIFEST_OUTPUT")
    project_version=$(jq -r '.resolved_project_version' "$MANIFEST_OUTPUT")

    [ "$project_package" = "drupal/cms" ]
    [ "$project_version" = "2.0.1" ]
}
