#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Link Repo-Managed Custom Modules into Generated Docroot.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This symlinks repo-managed custom modules into the generated Drupal codebase
# after Composer scaffolding has created the target web root.

# Load common utilities.
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/lib/bootstrap.sh"

SOURCE_MODULES_DIR="$PROJECT_ROOT/custom_modules"
TARGET_MODULES_DIR="$COMPOSER_ROOT/web/modules/custom"

if [ ! -d "$SOURCE_MODULES_DIR" ]; then
    log_warn "Custom modules source directory not found at $SOURCE_MODULES_DIR"
    exit 0
fi

mkdir -p "$TARGET_MODULES_DIR"

for module_dir in "$SOURCE_MODULES_DIR"/*; do
    if [ ! -d "$module_dir" ]; then
        continue
    fi

    if ! find "$module_dir" -maxdepth 1 -name '*.info.yml' | grep -q .; then
        continue
    fi

    module_name="$(basename "$module_dir")"
    target_dir="$TARGET_MODULES_DIR/$module_name"

    rm -rf "$target_dir"
    ln -s "$module_dir" "$target_dir"

    log_info "Linked custom module $module_name to $target_dir"
done
