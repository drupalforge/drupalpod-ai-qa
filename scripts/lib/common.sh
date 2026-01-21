#!/usr/bin/env bash
# Common utilities for DrupalPod AI QA scripts.
# Source this file at the beginning of each script for shared functionality.

set -eu -o pipefail

    # Initialize common paths and environment variables.
    # This should be called after SCRIPT_DIR is set by the calling script.
# IMPORTANT: SCRIPT_DIR must be set before calling this function.
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
# Logging helpers.
log_info() {
    printf "[DP] %s\n" "$*"
}

log_warn() {
    printf "[DP] %s\n" "$*"
}

log_error() {
    printf "[DP] %s\n" "$*"
}

# Check for jq dependency.
# Exits with error if jq is not found.
require_jq() {
    if ! command -v jq >/dev/null 2>&1; then
        echo "ERROR: 'jq' is required. Install jq to continue." >&2
        exit 1
    fi
}

# Backup composer.json and composer.lock files.
# Call before attempting risky composer operations.
backup_composer() {
    cp composer.json composer.json.bak
    cp composer.lock composer.lock.bak
}

# Restore composer.json and composer.lock from backup.
# Call after a failed composer operation to roll back.
restore_composer() {
    mv composer.json.bak composer.json
    mv composer.lock.bak composer.lock
}

# Clean up composer backup files.
# Call after a successful composer operation.
cleanup_composer_backup() {
    rm -f composer.json.bak composer.lock.bak
}

# Strip "drupal/" prefix from a package name.
# Example: "drupal/ai" -> "ai"
strip_drupal_prefix() {
    echo "${1#drupal/}"
}

# Try a composer operation with automatic backup/restore.
# Usage: try_composer_operation "operation description" command args...
# Returns 0 on success, 1 on failure.
try_composer_operation() {
    local description="$1"
    shift

    echo "  ${description}..."
    backup_composer

    if "$@" 2>/dev/null; then
        cleanup_composer_backup
        return 0
    else
        restore_composer
        return 1
    fi
}

# Normalize Composer version strings to Git-compatible versions.
# Direction: Composer-resolved version -> git ref/branch/tag.
# Examples:
#   dev-1.x       -> 1.x
#   1.2.x-dev    -> 1.2.x
#   1.2.3-dev    -> 1.2.3
#   1.2.3        -> 1.2.3
normalize_composer_version_to_git() {
    local version=${1:-}

    if [ -z "$version" ]; then
        echo ""
        return
    fi

    if [[ "$version" == dev-* ]]; then
        echo "${version#dev-}"
        return
    fi

    if [[ "$version" =~ ^([0-9]+\.[0-9]+)\.x-dev$ ]]; then
        echo "${BASH_REMATCH[1]}.x"
        return
    fi

    if [[ "$version" == *-dev ]]; then
        echo "${version%-dev}"
        return
    fi

    echo "$version"
}

# Normalize version input to a Composer constraint.
# Examples:
#   ""        -> "*"
#   "1"       -> "^1"
#   "1.2"     -> "~1.2"
#   "1.x"     -> "1.x-dev"
#   "1.2.x"   -> "1.2.x-dev"
#   "1.2.3"   -> "1.2.3"
normalize_version_to_composer() {
    local version=${1:-}

    if [ -z "$version" ]; then
        echo "*"
        return
    fi

    if [[ "$version" =~ ^[0-9]+$ ]]; then
        echo "^$version"
        return
    fi

    if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "~$version"
        return
    fi

    if [[ "$version" =~ ^[0-9]+\.x$ ]]; then
        echo "${version}-dev"
        return
    fi

    if [[ "$version" == *.x ]]; then
        echo "${version}-dev"
        return
    fi

    echo "$version"
}

# Normalize user-provided version input to a git ref-like string.
normalize_version_to_git_ref() {
    local version=${1:-}

    if [ -z "$version" ]; then
        echo ""
        return
    fi

    # Strip leading composer operators.
    version="${version#^}"
    version="${version#~}"

    if [[ "$version" =~ ^[0-9]+$ ]]; then
        echo "${version}.x"
        return
    fi

    if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "${version}.x"
        return
    fi

    echo "$version"
}

# Convert args into a JSON array string.
# Example: "a" "b" => ["a","b"]
build_json_array() {
    local items=("$@")
    local json='['

    for i in "${!items[@]}"; do
        if [ "$i" -gt 0 ]; then
            json+=","
        fi
        json+="\"${items[$i]}\""
    done

    json+=']'
    echo "$json"
}

# Enable composer-drupal-lenient with a list of allowed packages.
configure_lenient_mode() {
    local packages=("$@")

    if [ "${#packages[@]}" -eq 0 ]; then
        return
    fi

    local allow_list_json
    allow_list_json=$(build_json_array "${packages[@]}")

    composer config --no-plugins allow-plugins.mglaman/composer-drupal-lenient true
    composer require --prefer-dist -n --no-update "mglaman/composer-drupal-lenient:^1.0"
    composer config --json extra.drupal-lenient.allowed-list "$allow_list_json"
}
