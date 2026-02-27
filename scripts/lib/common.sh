#!/usr/bin/env bash
# Common utilities for DrupalPod AI QA scripts.
# Source this file at the beginning of each script for shared functionality.

set -eu -o pipefail

# Load split utility modules.
COMMON_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$COMMON_LIB_DIR/version_utils.sh"
source "$COMMON_LIB_DIR/composer_utils.sh"

# Initialize common paths and environment variables.
# This should be called after SCRIPT_DIR is set by the calling script.
# IMPORTANT: SCRIPT_DIR must be set before calling init_common().
# This centralizes path derivation so all scripts agree on project/layout roots.
init_common() {
    if [ -z "${SCRIPT_DIR:-}" ]; then
        echo "ERROR: SCRIPT_DIR must be set before calling init_common()" >&2
        exit 1
    fi

    project_root="$(cd "$SCRIPT_DIR/.." && pwd)"
    if [ "$(basename "$project_root")" = "docroot" ] && [ -d "$project_root/../scripts" ]; then
        project_root="$(cd "$project_root/.." && pwd)"
    fi

    export PROJECT_ROOT="$project_root"
    export APP_ROOT="${APP_ROOT:-${DP_APP_ROOT:-$PROJECT_ROOT}}"
    export COMPOSER_ROOT="${COMPOSER_ROOT:-${DP_COMPOSER_ROOT:-${DP_APP_ROOT:-$APP_ROOT/docroot}}}"
    export WEB_ROOT="${WEB_ROOT:-${DP_WEB_ROOT:-$COMPOSER_ROOT/web}}"
    if [ "$COMPOSER_ROOT" = "$APP_ROOT" ] && [ -d "$APP_ROOT/docroot" ]; then
        export COMPOSER_ROOT="$APP_ROOT/docroot"
    fi
    export DEV_PANEL_DIR="$PROJECT_ROOT/.devpanel"
    export LOG_DIR="$PROJECT_ROOT/logs"
    export DRUSH="$COMPOSER_ROOT/vendor/bin/drush"
    export MANIFEST_FILE="${DP_MODULE_MANIFEST:-$LOG_DIR/ai-manifest.json}"

    # Create log directory if it doesn't exist.
    mkdir -p "$LOG_DIR"
}

# Logging helpers (set NO_COLOR=1 to disable).
# Prefix intentionally stays short because logs are streamed through DDEV/CI.
log_info() {
    printf "[DP] %s\n" "$*" >&2
}

log_warn() {
    printf "[DP] %s\n" "$*" >&2
}

log_error() {
    printf "[DP] %s\n" "$*" >&2
}

# Retry helper for transient network/service failures.
# Usage: retry <command> [args...]
retry() {
    local max_attempts=${RETRY_MAX_ATTEMPTS:-3}
    local delay_seconds=${RETRY_DELAY_SECONDS:-2}
    local attempt=1

    while true; do
        if "$@"; then
            return 0
        fi
        if [ "$attempt" -ge "$max_attempts" ]; then
            return 1
        fi
        log_warn "Attempt ${attempt}/${max_attempts} failed. Retrying in ${delay_seconds}s: $*"
        sleep "$delay_seconds"
        attempt=$((attempt + 1))
    done
}

# Check for jq dependency.
# Exits with error if jq is not found.
require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: 'jq' is required. Install jq to continue." >&2
        exit 1
    fi
}

# Validate module names used for git/composer operations.
validate_module_name() {
    local module_name=$1
    if [[ ! "$module_name" =~ ^[a-z0-9_-]+$ ]]; then
        log_error "Invalid module name: $module_name"
        return 1
    fi
}

# Strip "drupal/" prefix from a package name.
# Example: "drupal/ai" -> "ai"
strip_drupal_prefix() {
    local module="${1#drupal/}"
    validate_module_name "$module"
    echo "$module"
}

# Convert args into a JSON array string.
# Example: "a" "b" => ["a","b"]
build_json_array() {
    require_jq
    jq -cn '$ARGS.positional' --args "$@"
}

# Enforce explicit module version when testing issue forks/branches.
require_issue_version() {
    local label="$1"
    local version_var="$2"
    local fork_var="$3"
    local branch_var="$4"
    local version_value="${!version_var:-}"
    local fork_value="${!fork_var:-}"
    local branch_value="${!branch_var:-}"

    if [ -n "$fork_value" ] || [ -n "$branch_value" ]; then
        if [ -z "$version_value" ]; then
            log_error "$label requires $version_var when using $fork_var/$branch_var."
            exit 1
        fi
    fi
}

validate_issue_version_requirements() {
    require_issue_version "AI module PR testing" "DP_AI_MODULE_VERSION" "DP_AI_ISSUE_FORK" "DP_AI_ISSUE_BRANCH"
    require_issue_version "Test module PR testing" "DP_TEST_MODULE_VERSION" "DP_TEST_MODULE_ISSUE_FORK" "DP_TEST_MODULE_ISSUE_BRANCH"
    require_issue_fork_matches_module "AI module PR testing" "DP_AI_MODULE" "DP_AI_ISSUE_FORK"
    require_issue_fork_matches_module "Test module PR testing" "DP_TEST_MODULE" "DP_TEST_MODULE_ISSUE_FORK"
}

require_issue_fork_matches_module() {
    local label="$1"
    local module_var="$2"
    local fork_var="$3"
    local module_value="${!module_var:-}"
    local fork_value="${!fork_var:-}"
    local expected_prefix=""

    [ -n "$module_value" ] || return 0
    [ -n "$fork_value" ] || return 0

    expected_prefix="${module_value}-"
    if [[ "$fork_value" != "$expected_prefix"* ]]; then
        log_error "$label fork/module mismatch: $fork_var='$fork_value' does not match $module_var='$module_value'."
        log_error "Expected fork name to start with '${expected_prefix}'."
        exit 1
    fi
}

reset_module_composer_json_if_dirty() {
    local repo_dir=$1

    if [ ! -e "$repo_dir/.git" ]; then
        return 0
    fi

    if ! git -C "$repo_dir" diff --quiet -- composer.json; then
        git -C "$repo_dir" checkout -- composer.json
    fi
}

ensure_module_submodule() {
    local module_name=$1
    local repo_dir="$PROJECT_ROOT/repos/$module_name"

    validate_module_name "$module_name"

    mkdir -p "$PROJECT_ROOT/repos"
    # If repo already exists locally (submodule checkout or direct clone),
    # reuse it instead of requiring valid .gitmodules mappings.
    if [ -e "$repo_dir/.git" ]; then
        reset_module_composer_json_if_dirty "$repo_dir"
        return 0
    fi

    # Repos are managed as git submodules so local checkouts are reproducible.
    if git submodule status "$repo_dir" >/dev/null 2>&1; then
        reset_module_composer_json_if_dirty "$repo_dir"
        git submodule update --init --recursive "$repo_dir"
        return 0
    fi

    # If submodule metadata is broken/missing, fall back to a direct clone
    # so setup can continue in local dev environments.
    if git ls-files --stage "$repo_dir" 2>/dev/null | grep -q '^160000 '; then
        log_warn "Submodule metadata missing for $repo_dir. Falling back to direct clone."
        if [ ! -d "$repo_dir" ]; then
            retry git clone "https://git.drupalcode.org/project/$module_name.git" "$repo_dir"
        fi
        reset_module_composer_json_if_dirty "$repo_dir"
        return 0
    fi

    if ! git submodule status "$repo_dir" >/dev/null 2>&1; then
        log_info "Adding module submodule: $module_name"
        git submodule add -f "https://git.drupalcode.org/project/$module_name.git" "$repo_dir"
        git config -f .gitmodules "submodule.$repo_dir.ignore" dirty
    fi
    reset_module_composer_json_if_dirty "$repo_dir"
    git submodule update --init --recursive "$repo_dir"
}

fetch_module_remotes() {
    local repo_dir=$1
    local issue_fork=${2:-}

    retry git -C "$repo_dir" fetch origin --tags --prune || true
    if [ -n "$issue_fork" ]; then
        git -C "$repo_dir" remote add "issue-$issue_fork" "https://git.drupalcode.org/issue/$issue_fork.git" 2>/dev/null || true
        if ! retry git -C "$repo_dir" fetch "issue-$issue_fork"; then
            log_warn "git fetch failed for issue-$issue_fork. Continuing with existing refs."
        fi
    fi
}

checkout_issue_branch() {
    local repo_dir=$1
    local issue_fork=$2
    local issue_branch=$3

    if ! git -C "$repo_dir" show-ref --verify --quiet "refs/remotes/issue-$issue_fork/$issue_branch"; then
        log_error "Branch $issue_branch not found on fork $issue_fork."
        return 1
    fi
    git -C "$repo_dir" checkout -B "$issue_branch" "issue-$issue_fork/$issue_branch"
    git -C "$repo_dir" branch --set-upstream-to="issue-$issue_fork/$issue_branch" "$issue_branch" >/dev/null 2>&1 || true
}

checkout_module_ref() {
    local repo_dir=$1
    local module_version=${2:-}

    if [ -n "$module_version" ]; then
        if [[ "$module_version" == *.x ]]; then
            if git -C "$repo_dir" show-ref --verify --quiet "refs/remotes/origin/$module_version"; then
                git -C "$repo_dir" checkout -B "$module_version" "origin/$module_version"
                return 0
            fi
            log_error "Branch $module_version not found on origin."
            return 1
        fi

        if git -C "$repo_dir" rev-parse "tags/$module_version" >/dev/null 2>&1; then
            git -C "$repo_dir" checkout "tags/$module_version"
            return 0
        fi
        if git -C "$repo_dir" show-ref --verify --quiet "refs/remotes/origin/$module_version"; then
            git -C "$repo_dir" checkout -B "$module_version" "origin/$module_version"
            return 0
        fi

        log_error "Version $module_version not found on origin."
        return 1
    fi

    local latest_tag=""
    latest_tag=$(git -C "$repo_dir" tag --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
    if [ -n "$latest_tag" ]; then
        git -C "$repo_dir" checkout "tags/$latest_tag"
    fi
}
