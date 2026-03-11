#!/usr/bin/env bash

set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Run PHPUnit for Repo-Managed Custom Drupal Modules
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/bootstrap.sh"

PROJECT_ROOT="${PROJECT_ROOT:-$(dirname "$SCRIPT_DIR")}"
CUSTOM_MODULES_ROOT="$PROJECT_ROOT/custom_modules"

if [ -n "${COMPOSER_ROOT:-}" ] && [ -f "${COMPOSER_ROOT}/composer.json" ]; then
    DETECTED_COMPOSER_ROOT="$COMPOSER_ROOT"
elif [ -n "${DRUPAL_PROJECT_FOLDER:-}" ] && [ -f "${DRUPAL_PROJECT_FOLDER}/composer.json" ]; then
    DETECTED_COMPOSER_ROOT="$DRUPAL_PROJECT_FOLDER"
elif [ -f "$PROJECT_ROOT/docroot/composer.json" ]; then
    DETECTED_COMPOSER_ROOT="$PROJECT_ROOT/docroot"
elif [ -f "$PROJECT_ROOT/composer.json" ]; then
    DETECTED_COMPOSER_ROOT="$PROJECT_ROOT"
else
    echo "Unable to locate Drupal composer root"
    exit 1
fi

COMPOSER_ROOT="$DETECTED_COMPOSER_ROOT"

if [ -n "${_WEB_ROOT:-}" ] && [ -d "$COMPOSER_ROOT/${_WEB_ROOT}" ]; then
    WEB_ROOT="$COMPOSER_ROOT/${_WEB_ROOT}"
elif [ -d "$COMPOSER_ROOT/web" ]; then
    WEB_ROOT="$COMPOSER_ROOT/web"
else
    echo "Unable to locate Drupal web root under $COMPOSER_ROOT"
    exit 1
fi

TARGET_CUSTOM_MODULES_ROOT="$WEB_ROOT/modules/custom"
PHPUNIT_CONFIG="$WEB_ROOT/core/phpunit.xml.dist"
PHPUNIT_BIN="$COMPOSER_ROOT/vendor/bin/phpunit"

if [ ! -d "$CUSTOM_MODULES_ROOT" ]; then
    echo "No custom_modules directory found at $CUSTOM_MODULES_ROOT"
    exit 0
fi

if ! find "$CUSTOM_MODULES_ROOT" -path '*/tests/src/*' -type f | grep -q .; then
    echo "No PHPUnit tests found under custom_modules"
    exit 0
fi

mkdir -p "$TARGET_CUSTOM_MODULES_ROOT"
mkdir -p "$WEB_ROOT/sites/simpletest/browser_output"

if [ ! -f "$COMPOSER_ROOT/composer.lock" ]; then
    echo "Missing composer.lock in $COMPOSER_ROOT"
    exit 1
fi

if [ ! -x "$PHPUNIT_BIN" ]; then
    echo "Installing Composer dependencies for PHPUnit..."
    COMPOSER_NO_AUDIT=1 composer -d "$COMPOSER_ROOT" install --prefer-dist --no-progress
fi

for module_dir in "$CUSTOM_MODULES_ROOT"/*; do
    if [ ! -d "$module_dir" ]; then
        continue
    fi

    module_name="$(basename "$module_dir")"
    if ! find "$module_dir" -maxdepth 1 -name '*.info.yml' | grep -q .; then
        continue
    fi

    target_dir="$TARGET_CUSTOM_MODULES_ROOT/$module_name"
    rm -rf "$target_dir"
    ln -s "$module_dir" "$target_dir"
done

cd "$WEB_ROOT"

echo "Running PHPUnit for custom modules..."
BROWSERTEST_OUTPUT_DIRECTORY="$WEB_ROOT/sites/simpletest/browser_output" \
BROWSERTEST_OUTPUT_BASE_URL=http://localhost:8080 \
SIMPLETEST_DB="sqlite://localhost/sites/default/files/.ht.sqlite" \
SIMPLETEST_BASE_URL=http://localhost \
SYMFONY_DEPRECATIONS_HELPER="ignoreFile=$WEB_ROOT/core/.deprecation-ignore.txt" \
php "../vendor/bin/phpunit" -c "$PHPUNIT_CONFIG" modules/custom "$@"
