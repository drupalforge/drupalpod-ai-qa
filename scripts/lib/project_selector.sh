#!/usr/bin/env bash
set -eu -o pipefail

# Resolve the base Drupal project and version constraint from DP_* inputs.
# Outputs:
#   COMPOSER_PROJECT: drupal/cms or drupal/recommended-project
#   INSTALL_VERSION: version constraint for composer create-project (may be empty)
resolve_project_selection() {
    if [ "${COMPOSER_PROJECT+set}" = "set" ] && [ "${INSTALL_VERSION+set}" = "set" ]; then
        return
    fi

    local starter_template="${DP_STARTER_TEMPLATE:-cms}"
    local dp_version="${DP_VERSION:-}"

    COMPOSER_PROJECT=""
    INSTALL_VERSION=""

    if [ "$starter_template" = "cms" ]; then
        COMPOSER_PROJECT="drupal/cms"
        # CMS versions use exact tags or x-dev for branches (e.g., 1.x -> 1.x-dev).
        if [ -n "$dp_version" ]; then
            case $dp_version in
            *.x)
                INSTALL_VERSION="$dp_version-dev"
                ;;
            *)
                INSTALL_VERSION="$dp_version"
                ;;
            esac
        fi
    else
        COMPOSER_PROJECT="drupal/recommended-project"
        # Core versions: exact versions use ~ for patch updates (e.g., 10.4.0 -> ~10.4.0),
        # while x branches use x-dev (e.g., 10.4.x -> 10.4.x-dev).
        if [ -n "$dp_version" ]; then
            case $dp_version in
            *.x)
                INSTALL_VERSION="$dp_version-dev"
                ;;
            *)
                INSTALL_VERSION="~$dp_version"
                ;;
            esac
        fi
    fi

    export COMPOSER_PROJECT
    export INSTALL_VERSION
}
