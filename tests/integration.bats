#!/usr/bin/env bats

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Integration Tests - Verify Plan-Driven Decisions
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    mkdir -p "$PROJECT_ROOT/logs"
    cat > "$PROJECT_ROOT/logs/ai-manifest.json" <<'JSON'
{
  "packages": [
    {"name": "drupal/ai", "version": "2.0.x-dev"},
    {"name": "drupal/ai_search", "version": "2.0.0"},
    {"name": "drupal/ai_provider_litellm", "version": "dev-1.x"}
  ]
}
JSON

    # shellcheck disable=SC1090
    source "$PROJECT_ROOT/scripts/lib/common.sh"
    eval "$(sed -n '/^load_manifest_modules()/,/^}/p' "$PROJECT_ROOT/scripts/clone_modules.sh")"
}

teardown() {
    rm -rf "$PROJECT_ROOT/logs"
}

@test "plan modules map to git versions" {
    while read -r package version; do
        git_version=$(normalize_composer_version_to_git "$version")
        case "$package" in
        drupal/ai)
            [ "$git_version" = "2.0.x" ]
            ;;
        drupal/ai_search)
            [ "$git_version" = "2.0.0" ]
            ;;
        drupal/ai_provider_litellm)
            [ "$git_version" = "1.x" ]
            ;;
        esac
    done < <(load_manifest_modules "$PROJECT_ROOT/logs/ai-manifest.json")
}

@test "plan module list drives composer modules" {
    COMPATIBLE_MODULES=""

    while read -r package _version; do
        module_name=${package#drupal/}
        if [ -z "$COMPATIBLE_MODULES" ]; then
            COMPATIBLE_MODULES="$module_name"
        else
            COMPATIBLE_MODULES="$COMPATIBLE_MODULES,$module_name"
        fi
    done < <(load_manifest_modules "$PROJECT_ROOT/logs/ai-manifest.json")

    [ "$COMPATIBLE_MODULES" = "ai,ai_search,ai_provider_litellm" ]
}
