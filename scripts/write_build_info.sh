#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Export DrupalPod Build Metadata for Drupal Status Report.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This script transforms the resolver manifest plus current git checkout
# information into a small JSON artifact that Drupal can display.

# Load common utilities.
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/lib/bootstrap.sh"
require_jq

if [ ! -f "$MANIFEST_FILE" ]; then
    log_warn "Module manifest not found at $MANIFEST_FILE; skipping build info export."
    exit 0
fi

OUTPUT_DIR="$COMPOSER_ROOT/build"
OUTPUT_FILE="$OUTPUT_DIR/drupalpod-build-info.json"
MODULES_TMP_FILE="$(mktemp)"

cleanup() {
    rm -f "$MODULES_TMP_FILE"
}

trap cleanup EXIT

mkdir -p "$OUTPUT_DIR"

build_module_json() {
    local package_name=$1
    local composer_version=$2
    local module_name=""
    local repo_dir=""
    local git_ref=""
    local git_branch=""
    local issue_fork=""
    local issue_branch=""

    module_name="$(strip_drupal_prefix "$package_name")"
    repo_dir="$PROJECT_ROOT/repos/$module_name"

    if [ -d "$repo_dir" ] && git -C "$repo_dir" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        git_ref="$(git -C "$repo_dir" describe --tags --always --dirty 2>/dev/null || git -C "$repo_dir" rev-parse --short HEAD)"
        git_branch="$(git -C "$repo_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
        if [ "$git_branch" = "HEAD" ]; then
            git_branch=""
        fi
    fi

    if [ "${module_name}" = "${DP_AI_MODULE:-}" ]; then
        issue_fork="${DP_AI_ISSUE_FORK:-}"
        issue_branch="${DP_AI_ISSUE_BRANCH:-}"
    elif [ -n "${DP_TEST_MODULE:-}" ] && [ "${module_name}" = "${DP_TEST_MODULE}" ]; then
        issue_fork="${DP_TEST_MODULE_ISSUE_FORK:-}"
        issue_branch="${DP_TEST_MODULE_ISSUE_BRANCH:-}"
    fi

    jq -cn \
        --arg package_name "$package_name" \
        --arg machine_name "$module_name" \
        --arg composer_version "$composer_version" \
        --arg git_ref "$git_ref" \
        --arg git_branch "$git_branch" \
        --arg issue_fork "$issue_fork" \
        --arg issue_branch "$issue_branch" \
        '{
            package_name: $package_name,
            machine_name: $machine_name,
            composer_version: $composer_version,
            git_ref: $git_ref,
            git_branch: $git_branch,
            issue_fork: $issue_fork,
            issue_branch: $issue_branch
        }'
}

while read -r package version; do
    build_module_json "$package" "$version" >> "$MODULES_TMP_FILE"
    printf '\n' >> "$MODULES_TMP_FILE"
done < <(jq -r '.packages[]? | "\(.name) \(.version)"' "$MANIFEST_FILE")

MODULES_JSON='[]'
if [ -s "$MODULES_TMP_FILE" ]; then
    MODULES_JSON="$(jq -s '.' "$MODULES_TMP_FILE")"
fi

jq -n \
    --slurpfile manifest "$MANIFEST_FILE" \
    --argjson modules "$MODULES_JSON" \
    '($manifest[0] // {}) as $manifest
    | {
        generated_at: ($manifest.generated_at // ""),
        starter_template: ($manifest.starter_template // ""),
        dp_version: ($manifest.dp_version // ""),
        resolution_mode: ($manifest.resolution_mode // $manifest.mode // 0),
        compatibility: ($manifest.compatibility // ""),
        forced_reason: ($manifest.forced_reason // ""),
        resolved_project_package: ($manifest.resolved_project_package // ""),
        resolved_project_version: ($manifest.resolved_project_version // ""),
        resolved_cms_version: ($manifest.resolved_cms_version // ""),
        resolved_core_version: ($manifest.resolved_core_version // ""),
        requested_ai_module: (env.DP_AI_MODULE // ""),
        requested_ai_version: (env.DP_AI_MODULE_VERSION // ""),
        requested_ai_issue_fork: (env.DP_AI_ISSUE_FORK // ""),
        requested_ai_issue_branch: (env.DP_AI_ISSUE_BRANCH // ""),
        requested_test_module: (env.DP_TEST_MODULE // ""),
        requested_test_version: (env.DP_TEST_MODULE_VERSION // ""),
        requested_test_issue_fork: (env.DP_TEST_MODULE_ISSUE_FORK // ""),
        requested_test_issue_branch: (env.DP_TEST_MODULE_ISSUE_BRANCH // ""),
        requested_packages: ($manifest.requested_packages // []),
        skipped_packages: ($manifest.skipped_packages // []),
        modules: $modules
      }' > "$OUTPUT_FILE"

log_info "Wrote DrupalPod build metadata to $OUTPUT_FILE"
