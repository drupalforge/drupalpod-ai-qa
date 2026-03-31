#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Run PHPUnit tests for custom modules.
# Builds a minimal Drupal project from scratch so modules are installed
# from packagist rather than from local path repos / git submodules.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILD_DIR="${PHPUNIT_BUILD_DIR:-/tmp/drupal-phpunit-build}"

echo "Building fresh Drupal project at $BUILD_DIR..."
rm -rf "$BUILD_DIR"

composer create-project drupal/recommended-project "$BUILD_DIR" \
    --no-interaction --no-install --prefer-dist

cd "$BUILD_DIR"

composer config allow-plugins.composer/installers true
composer config allow-plugins.drupal/core-project-message true
composer config allow-plugins.drupal/core-composer-scaffold true
composer config allow-plugins.drupal/core-vendor-hardening true

composer require --no-update \
    drupal/ai:^1 \
    drupal/key:^1.17 \
    drupal/easy_encryption:^1.0 \
    drupal/ai_provider_openai:^1

composer require --dev --no-update \
    "drupal/core-dev":* \
    "phpspec/prophecy-phpunit":^2

composer update --no-interaction --prefer-dist --no-progress

# Link custom modules into the build.
mkdir -p web/modules/custom
for module_dir in "$PROJECT_ROOT/custom_modules"/*/; do
    module_name="$(basename "$module_dir")"
    if find "$module_dir" -maxdepth 1 -name '*.info.yml' | grep -q .; then
        ln -sf "$module_dir" "web/modules/custom/$module_name"
        echo "Linked $module_name"
    fi
done

# Set up files directory for sqlite.
mkdir -p web/sites/default/files
chmod -R 777 web/sites/default/files

export SIMPLETEST_DB="sqlite://localhost/sites/default/files/.ht.sqlite"
export SIMPLETEST_BASE_URL="http://localhost"
export BROWSERTEST_OUTPUT_DIRECTORY="$BUILD_DIR/web/sites/simpletest/browser_output"

mkdir -p "$BROWSERTEST_OUTPUT_DIRECTORY"

echo "Running PHPUnit..."
php "$BUILD_DIR/vendor/phpunit/phpunit/phpunit" \
    -c "$BUILD_DIR/web/core/phpunit.xml.dist" \
    "$BUILD_DIR/web/modules/custom/drupalpod_ai_qa" \
    --log-junit "$PROJECT_ROOT/logs/phpunit.xml" \
    "$@"
