#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Install DrupalPod Build Info Module into Generated Docroot.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This symlinks the repo-managed custom module into the generated Drupal
# codebase after Composer scaffolding has created the target web root.

# Load common utilities.
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/lib/bootstrap.sh"

SOURCE_MODULE_DIR="$PROJECT_ROOT/custom_modules/drupalpod_build_info"
TARGET_MODULE_DIR="$COMPOSER_ROOT/web/modules/custom/drupalpod_build_info"

if [ ! -d "$SOURCE_MODULE_DIR" ]; then
    log_warn "DrupalPod build info module source not found at $SOURCE_MODULE_DIR"
    exit 0
fi

mkdir -p "$COMPOSER_ROOT/web/modules/custom"
rm -rf "$TARGET_MODULE_DIR"
ln -s "$SOURCE_MODULE_DIR" "$TARGET_MODULE_DIR"

log_info "Linked DrupalPod build info module to $TARGET_MODULE_DIR"
