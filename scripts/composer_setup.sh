#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Setup Composer Project from CMS/Core Template.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This script creates a new Drupal project (CMS or Core), configures it,
# and adds AI modules as path repositories.

# Load common utilities (skip if already loaded by parent script).
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/lib/common.sh"
    init_common
fi

cd "$APP_ROOT"

# Determine which starter template to use.
# Options: "cms" or "core"
STARTER_TEMPLATE="${DP_STARTER_TEMPLATE:-cms}"

# Resolve composer project + version constraint in one place.
COMPOSER_PROJECT=""
INSTALL_VERSION=""

if [ "$STARTER_TEMPLATE" = "cms" ]; then
    COMPOSER_PROJECT="drupal/cms"
else
    COMPOSER_PROJECT="drupal/recommended-project"
fi

if [ -n "${DP_VERSION:-}" ]; then
    INSTALL_VERSION="$(normalize_version_to_composer "${DP_VERSION}")"
fi

export COMPOSER_PROJECT
export INSTALL_VERSION

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
if [ -n "$INSTALL_VERSION" ]; then
    time composer create-project --prefer-dist -n --no-install "$COMPOSER_PROJECT":"$INSTALL_VERSION" temp-composer-files
else
    time composer create-project --prefer-dist -n --no-install "$COMPOSER_PROJECT" temp-composer-files
fi

# Copy all files (including hidden files) from temp to docroot.
cp -r temp-composer-files/. .

# Clean up temp directory.
rm -rf temp-composer-files

# Programmatically fix Composer 2.2 allow-plugins to avoid errors.
# IMPORTANT: Do this FIRST before any other composer config commands to avoid warnings.
ALLOWED_PLUGINS=(
    "composer/installers:true"
    "drupal/core-project-message:true"
    "drupal/core-vendor-hardening:true"
    "drupal/core-composer-scaffold:true"
    "dealerdirect/phpcodesniffer-composer-installer:true"
    "phpstan/extension-installer:true"
    "mglaman/composer-drupal-lenient:true"
    "drupalpod/ai-lenient-plugin:true"
    "php-http/discovery:true"
    "tbachert/spi:false"
    "cweagans/composer-patches:true"
)

for plugin_config in "${ALLOWED_PLUGINS[@]}"; do
    plugin="${plugin_config%:*}"
    value="${plugin_config#*:}"
    composer config --no-plugins "allow-plugins.${plugin}" "$value"
done

# Set minimum-stability to dev to allow alpha/beta packages (needed for dev versions).
composer config minimum-stability dev

# Allow patches to fail without stopping installation.
composer config extra.composer-exit-on-patch-failure false

# If forcing dependencies, enable lenient mode so explicit AI versions can
# bypass CMS/core constraints during the actual install.
if [ "${DP_FORCE_DEPENDENCIES:-0}" = "1" ] && [ -n "${DP_AI_MODULE_VERSION:-}" ]; then
    LENIENT_PACKAGES=()
    LENIENT_PACKAGES+=("drupal/${DP_AI_MODULE:-ai}")
    if [ -n "${DP_TEST_MODULE:-}" ]; then
        LENIENT_PACKAGES+=("drupal/${DP_TEST_MODULE}")
    fi
    configure_lenient_mode "${LENIENT_PACKAGES[@]}"
fi

# Scaffold settings.php.
composer config --json extra.drupal-scaffold.file-mapping '{"[web-root]/sites/default/settings.php":{"path":"web/core/assets/scaffold/files/default.settings.php","overwrite":false}}'
composer config scripts.post-drupal-scaffold-cmd \
    "cd web/sites/default && test -z \"\$(grep 'include \\\$devpanel_settings;' settings.php)\" && patch -Np1 -r /dev/null < $DEV_PANEL_DIR/drupal-settings.patch || :"

# If forcing dependencies, enable the local AI lenient plugin.
if [ "${DP_FORCE_DEPENDENCIES:-0}" = "1" ]; then
    plugin_path="$PROJECT_ROOT/src/ai-lenient-plugin"
    if [ -d "$plugin_path" ]; then
        composer config --no-plugins repositories.ai-lenient-plugin \
            "{\"type\": \"path\", \"url\": \"$plugin_path\", \"options\": {\"symlink\": true}}"
        composer require --prefer-dist -n --no-progress "drupalpod/ai-lenient-plugin:*@dev"
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI MODULES FROM GIT (Path Repositories)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Add path repositories for all resolved AI modules
# All modules must be compatible (resolved via Composer dependency resolution)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ -n "${COMPATIBLE_MODULES:-}" ]; then
    echo "Adding path repositories for AI modules..."

    IFS=',' read -ra MODULES <<< "$COMPATIBLE_MODULES"
    for module in "${MODULES[@]}"; do
        module=$(echo "$module" | xargs)  # Trim whitespace

        if [ -z "$module" ]; then
            continue
        fi

        repo_path="$PROJECT_ROOT/repos/$module"
        if [ -d "$repo_path" ]; then
            echo "  - Adding path repository for: $module"
            composer config --no-plugins repositories."$module"-git \
                "{\"type\": \"path\", \"url\": \"$repo_path\", \"options\": {\"symlink\": true}}"

            # Require from path (use *@dev to accept version from module's composer.json).
            composer require --prefer-dist -n --no-update "drupal/$module:*@dev"
        fi
    done

    echo "Path repositories added for AI modules!"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI DEPENDENCIES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

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
    composer require --prefer-dist -n --no-update --dev \
        cweagans/composer-patches:^2@beta \
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
    # Core template does not include drush by default, so we add it here.
    composer require --prefer-dist -n --no-update \
        drush/drush \
        cweagans/composer-patches:^2@beta \
        drupal/search_api \
        drupal/search_api_db \
        drupal/token
fi
