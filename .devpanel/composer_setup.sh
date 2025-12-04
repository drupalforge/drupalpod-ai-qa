#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Directory Setup (works in both DDEV and GitHub Actions environments)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Find the .devpanel directory (where this script lives)
DEVPANEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root is one level up from .devpanel
PROJECT_ROOT="$(dirname "$DEVPANEL_DIR")"
# APP_ROOT is the composer root (from environment or default to PROJECT_ROOT)
APP_ROOT="${APP_ROOT:-$PROJECT_ROOT}"

cd "$APP_ROOT"

# Determine which starter template to use.
# Options: "cms" or "core"
STARTER_TEMPLATE="${DP_STARTER_TEMPLATE:-cms}"

# Determine the composer package and version.
if [ "$STARTER_TEMPLATE" = "cms" ]; then
    COMPOSER_PROJECT="drupal/cms"
    # For CMS versions: 1.x, 1.0.0, 2.0.0, etc.
    d="$DP_VERSION"
    case $d in
    *.x)
        install_version="$d"-dev
        ;;
    *)
        install_version="$d"
        ;;
    esac
else
    COMPOSER_PROJECT="drupal/recommended-project"
    # For core versions: 11.x, 11.2.8, etc.
    d="$DP_VERSION"
    case $d in
    *.x)
        install_version="$d"-dev
        ;;
    *)
        install_version=~"$d"
        ;;
    esac
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Generate composer.json from CMS/Core template using temp directory
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Why do we copy it to temp?
# - `composer create-project` requires an empty/non-existent target directory
# - Our project root may have existing files (git, config, etc.)
# - Solution: Create in temp, copy everything over, then customize composer.json
# - This is safer than deleting project root first (preserves files if script fails)
#
# Clean up temp directory if it exists from previous runs.
rm -rf temp-composer-files

# Create the project template in temp directory.
if [ -n "$install_version" ]; then
    time composer create-project -n --no-install "$COMPOSER_PROJECT":"$install_version" temp-composer-files
else
    time composer create-project -n --no-install "$COMPOSER_PROJECT" temp-composer-files
fi

# Copy all files (including hidden files) from temp to docroot.
cp -r temp-composer-files/. .

# Clean up temp directory.
rm -rf temp-composer-files

# Set minimum-stability to dev to allow alpha/beta packages (needed for dev versions).
composer config minimum-stability dev

# Allow patches to fail without stopping installation.
composer config extra.composer-exit-on-patch-failure false

# Programmatically fix Composer 2.2 allow-plugins to avoid errors.
composer config --no-plugins allow-plugins.composer/installers true
composer config --no-plugins allow-plugins.drupal/core-project-message true
composer config --no-plugins allow-plugins.drupal/core-vendor-hardening true
composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
composer config --no-plugins allow-plugins.dealerdirect/phpcodesniffer-composer-installer true
composer config --no-plugins allow-plugins.phpstan/extension-installer true
composer config --no-plugins allow-plugins.mglaman/composer-drupal-lenient true
composer config --no-plugins allow-plugins.php-http/discovery true
composer config --no-plugins allow-plugins.tbachert/spi false

# Scaffold settings.php.
composer config extra.drupal-scaffold.file-mapping '{"[web-root]/sites/default/settings.php":{"path":"web/core/assets/scaffold/files/default.settings.php","overwrite":false}}'
composer config scripts.post-drupal-scaffold-cmd \
    'cd web/sites/default && test -z "$(grep '\''include \$devpanel_settings;'\'' settings.php)" && patch -Np1 -r /dev/null < $DIR/drupal-settings.patch || :'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI MODULES FROM GIT (Path Repositories)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Add path repositories ONLY for compatible AI modules
# Incompatible modules are cloned (available in repos/) but not added to composer
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ -n "${COMPATIBLE_AI_MODULES:-}" ]; then
    echo "Adding path repositories for compatible AI modules..."

    IFS=',' read -ra MODULES <<< "$COMPATIBLE_AI_MODULES"
    for module in "${MODULES[@]}"; do
        module=$(echo "$module" | xargs)  # Trim whitespace

        if [ -z "$module" ]; then
            continue
        fi

        if [ -d "$APP_ROOT/repos/$module" ]; then
            echo "  - Adding path repository for: $module"
            composer config --no-plugins repositories."$module"-git \
                "{\"type\": \"path\", \"url\": \"$APP_ROOT/repos/$module\", \"options\": {\"symlink\": true}}"

            # Require from path (use *@dev to accept version from module's composer.json).
            composer require -n --no-update "drupal/$module:*@dev"
        fi
    done

    echo "Path repositories added for compatible AI modules!"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI DEPENDENCIES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Enable Composer Patches plugin (needed for applying patches from drupal.org).
composer config --no-plugins allow-plugins.cweagans/composer-patches true

if [ "$STARTER_TEMPLATE" = "cms" ]; then
    echo "Adding CMS dependencies (full setup with webform libraries)..."

    # Add JavaScript library repositories for Webform support.
    composer config repositories.tippyjs '{
        "type": "package",
        "package": {
            "name": "tippyjs/tippyjs",
            "version": "6.3.7",
            "type": "drupal-library",
            "extra": {
                "installer-name": "tippyjs"
            },
            "dist": {
                "url": "https://registry.npmjs.org/tippy.js/-/tippy.js-6.3.7.tgz",
                "type": "tar"
            },
            "license": "MIT"
        }
    }'

    composer config repositories.tabby '{
        "type": "package",
        "package": {
            "name": "tabby/tabby",
            "version": "12.0.3",
            "type": "drupal-library",
            "extra": {
                "installer-name": "tabby"
            },
            "dist": {
                "url": "https://github.com/cferdinandi/tabby/archive/refs/tags/v12.0.3.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories.signature_pad '{
        "type": "package",
        "package": {
            "name": "signature_pad/signature_pad",
            "version": "2.3.0",
            "type": "drupal-library",
            "extra": {
                "installer-name": "signature_pad"
            },
            "dist": {
                "url": "https://github.com/szimek/signature_pad/archive/refs/tags/v2.3.0.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories.progress-tracker '{
        "type": "package",
        "package": {
            "name": "progress-tracker/progress-tracker",
            "version": "2.0.7",
            "type": "drupal-library",
            "extra": {
                "installer-name": "progress-tracker"
            },
            "dist": {
                "url": "https://github.com/NigelOToole/progress-tracker/archive/refs/tags/2.0.7.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories.popperjs '{
        "type": "package",
        "package": {
            "name": "popperjs/popperjs",
            "version": "2.11.6",
            "type": "drupal-library",
            "extra": {
                "installer-name": "popperjs"
            },
            "dist": {
                "url": "https://registry.npmjs.org/@popperjs/core/-/core-2.11.6.tgz",
                "type": "tar"
            },
            "license": "MIT"
        }
    }'

    composer config repositories."jquery.timepicker" '{
        "type": "package",
        "package": {
            "name": "jquery/timepicker",
            "version": "1.14.0",
            "type": "drupal-library",
            "extra": {
                "installer-name": "jquery.timepicker"
            },
            "dist": {
                "url": "https://github.com/jonthornton/jquery-timepicker/archive/refs/tags/1.14.0.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories."jquery.textcounter" '{
        "type": "package",
        "package": {
            "name": "jquery/textcounter",
            "version": "0.9.1",
            "type": "drupal-library",
            "extra": {
                "installer-name": "jquery.textcounter"
            },
            "dist": {
                "url": "https://github.com/ractoon/jQuery-Text-Counter/archive/refs/tags/0.9.1.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories."jquery.select2" '{
        "type": "package",
        "package": {
            "name": "jquery/select2",
            "version": "4.0.13",
            "type": "drupal-library",
            "extra": {
                "installer-name": "jquery.select2"
            },
            "dist": {
                "url": "https://github.com/select2/select2/archive/refs/tags/4.0.13.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories."jquery.rateit" '{
        "type": "package",
        "package": {
            "name": "jquery/rateit",
            "version": "1.1.5",
            "type": "drupal-library",
            "extra": {
                "installer-name": "jquery.rateit"
            },
            "dist": {
                "url": "https://github.com/gjunge/rateit.js/archive/refs/tags/1.1.5.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories."jquery.intl-tel-input" '{
        "type": "package",
        "package": {
            "name": "jquery/intl-tel-input",
            "version": "17.0.19",
            "type": "drupal-library",
            "extra": {
                "installer-name": "jquery.intl-tel-input"
            },
            "dist": {
                "url": "https://github.com/jackocnr/intl-tel-input/archive/refs/tags/v17.0.19.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories."jquery.inputmask" '{
        "type": "package",
        "package": {
            "name": "jquery/inputmask",
            "version": "5.0.9",
            "type": "drupal-library",
            "extra": {
                "installer-name": "jquery.inputmask"
            },
            "dist": {
                "url": "https://github.com/RobinHerbots/jquery.inputmask/archive/refs/tags/5.0.9.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    composer config repositories.codemirror '{
        "type": "package",
        "package": {
            "name": "codemirror/codemirror",
            "version": "5.65.12",
            "type": "drupal-library",
            "extra": {
                "installer-name": "codemirror"
            },
            "dist": {
                "url": "https://github.com/components/codemirror/archive/refs/tags/5.65.12.zip",
                "type": "zip"
            },
            "license": "MIT"
        }
    }'

    # Require all CMS dependencies (Webform libraries only - AI modules come from git).
    composer require -n --no-update --dev \
        cweagans/composer-patches:^2@beta \
        drush/drush:^13.6 \
        codemirror/codemirror \
        jquery/inputmask \
        jquery/intl-tel-input \
        jquery/rateit \
        jquery/select2 \
        jquery/textcounter \
        jquery/timepicker \
        popperjs/popperjs \
        progress-tracker/progress-tracker \
        signature_pad/signature_pad \
        tabby/tabby \
        tippyjs/tippyjs

else
    echo "Adding Core AI dependencies (lean setup for quick PR/issue testing)..."

    # Core variant: Search only - AI modules come from git via path repos.
    composer require -n --no-update \
        cweagans/composer-patches:^2@beta \
        drush/drush:^13.6 \
        drupal/search_api \
        drupal/search_api_db \
        drupal/token
fi
