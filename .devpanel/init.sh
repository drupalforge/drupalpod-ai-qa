#!/usr/bin/env bash
set -eu -o pipefail

# Thin wrapper to keep DevPanel script location.
# All the build scripts are in the "scripts" directory,
# so ddev and other tools can find them easily and it
# makes more sense for shared usage.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# Default composer/web roots for DevPanel when only DP_APP_ROOT is provided.
if [ -n "${DP_APP_ROOT:-}" ] && [ -z "${DP_COMPOSER_ROOT:-}" ]; then
    # If APP_ROOT already points at docroot, reuse it; otherwise append /docroot.
    case "$DP_APP_ROOT" in
        */docroot) export DP_COMPOSER_ROOT="$DP_APP_ROOT" ;;
        *) export DP_COMPOSER_ROOT="$DP_APP_ROOT/docroot" ;;
    esac
fi
if [ -z "${DP_WEB_ROOT:-}" ] && [ -n "${DP_COMPOSER_ROOT:-}" ]; then
    # WEB_ROOT defaults to the Drupal web directory under the composer root.
    export DP_WEB_ROOT="$DP_COMPOSER_ROOT/web"
fi
exec "$SCRIPT_DIR/../scripts/init.sh"
