#!/usr/bin/env bats

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Test Suite for clone_modules.sh
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    mkdir -p "$PROJECT_ROOT/logs"
    cat > "$PROJECT_ROOT/logs/ai-manifest.json" <<'JSON'
{
  "packages": [
    {"name": "drupal/ai", "version": "2.0.0"},
    {"name": "drupal/ai_search", "version": "2.0.x-dev"},
    {"name": "drupal/ai_provider_litellm", "version": "dev-1.x"}
  ],
  "skipped_packages": ["drupal/ai_agents"]
}
JSON

    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/scripts/lib/common.sh"
    eval "$(sed -n '/^load_manifest_modules()/,/^}/p' "$PROJECT_ROOT/scripts/clone_modules.sh")"
    eval "$(sed -n '/^load_manifest_skipped_modules()/,/^}/p' "$PROJECT_ROOT/scripts/clone_modules.sh")"
}

teardown() {
    rm -rf "$PROJECT_ROOT/logs"
}

@test "normalize composer version: 2.0.x-dev -> 2.0.x" {
    result=$(normalize_composer_version_to_git "2.0.x-dev")
    [ "$result" = "2.0.x" ]
}

@test "normalize composer version: dev-1.x -> 1.x" {
    result=$(normalize_composer_version_to_git "dev-1.x")
    [ "$result" = "1.x" ]
}

@test "normalize composer version: 2.0.0 -> 2.0.0" {
    result=$(normalize_composer_version_to_git "2.0.0")
    [ "$result" = "2.0.0" ]
}

@test "load_manifest_modules returns package names and versions" {
    output=$(load_manifest_modules "$PROJECT_ROOT/logs/ai-manifest.json")
    [[ "$output" =~ "drupal/ai 2.0.0" ]]
    [[ "$output" =~ "drupal/ai_search 2.0.x-dev" ]]
    [[ "$output" =~ "drupal/ai_provider_litellm dev-1.x" ]]
}

@test "load_manifest_skipped_modules returns skipped package names" {
    output=$(load_manifest_skipped_modules "$PROJECT_ROOT/logs/ai-manifest.json")
    [[ "$output" =~ "drupal/ai_agents" ]]
}
