#!/usr/bin/env bash
set -eu -o pipefail
cd $APP_ROOT

# Determine which starter template to use (default: recommended-project)
# Options: "recommended" or "cms"
STARTER_TEMPLATE="${DP_STARTER_TEMPLATE:-recommended}"

# Set the composer package based on template choice
if [ "$STARTER_TEMPLATE" = "cms" ]; then
    COMPOSER_PROJECT="drupal/cms"
    # For Drupal CMS, use latest version if DP_CORE_VERSION is set to a Drupal core version
    # CMS has its own versioning (1.0.0, 1.1.0, etc) separate from core
    # If DP_CORE_VERSION is empty or looks like a core version, use latest CMS
    if [ -z "$DP_CORE_VERSION" ] || [[ "$DP_CORE_VERSION" =~ ^[0-9]+\.[0-9]+\. ]]; then
        install_version=""  # Use latest
    else
        # Allow explicit CMS versions like "1.1.x-dev" or "1.0.0"
        d="$DP_CORE_VERSION"
        case $d in
        *.x)
            install_version="$d"-dev
            ;;
        *)
            install_version=~"$d"
            ;;
        esac
    fi
else
    COMPOSER_PROJECT="drupal/recommended-project"
    # For versions end with x - add `-dev` suffix (ie. 9.3.x-dev)
    # For versions without x - add `~` prefix (ie. ~9.2.0)
    d="$DP_CORE_VERSION"
    case $d in
    *.x)
        install_version="$d"-dev
        ;;
    *)
        install_version=~"$d"
        ;;
    esac
fi

if [ ! -f composer.json ]; then
    # Create required composer.json and composer.lock files
    if [ -n "$install_version" ]; then
        time composer create-project -n --no-install "$COMPOSER_PROJECT":"$install_version" temp-composer-files
    else
        time composer create-project -n --no-install "$COMPOSER_PROJECT" temp-composer-files
    fi
    # Copy all files and directories (including hidden files) from temp directory
    cp -r "$APP_ROOT"/temp-composer-files/. "$APP_ROOT"/.
    rm -rf "$APP_ROOT"/temp-composer-files
fi

# Programmatically fix Composer 2.2 allow-plugins to avoid errors
composer config --no-plugins allow-plugins.composer/installers true
composer config --no-plugins allow-plugins.drupal/core-project-message true
composer config --no-plugins allow-plugins.drupal/core-vendor-hardening true
composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
composer config --no-plugins allow-plugins.dealerdirect/phpcodesniffer-composer-installer true
composer config --no-plugins allow-plugins.phpstan/extension-installer true
composer config --no-plugins allow-plugins.mglaman/composer-drupal-lenient true
composer config --no-plugins allow-plugins.php-http/discovery true
composer config --no-plugins allow-plugins.tbachert/spi false

# Add project source code as symlink (to repos/name_of_project)
# double quotes explained - https://stackoverflow.com/a/1250279/5754049
if [ -n "$DP_PROJECT_NAME" ]; then
    composer --no-plugins config \
        repositories.core1 \
        '{"type": "path", "url": "repos/'"$DP_PROJECT_NAME"'", "options": {"symlink": true}}'

    composer --no-plugins config minimum-stability dev
fi

# Scaffold settings.php.
composer config -jm extra.drupal-scaffold.file-mapping '{
    "[web-root]/sites/default/settings.php": {
        "path": "web/core/assets/scaffold/files/default.settings.php",
        "overwrite": false
    }
}'
composer config scripts.post-drupal-scaffold-cmd \
    'cd web/sites/default && test -z "$(grep '\''include \$devpanel_settings;'\'' settings.php)" && patch -Np1 -r /dev/null < $APP_ROOT/.devpanel/drupal-settings.patch || :'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI DEPENDENCIES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Enable Composer Patches plugin (useful for applying patches from drupal.org)
composer config --no-plugins allow-plugins.cweagans/composer-patches true

if [ "$STARTER_TEMPLATE" = "cms" ]; then
    echo "Adding CMS AI dependencies (full setup with webform libraries)..."

    # Add JavaScript library repositories for Webform support
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

    # Require all CMS dependencies (AI + Webform libraries)
    composer require -n --no-update \
        cweagans/composer-patches:^2@beta \
        drupal/ai_provider_litellm:@beta \
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

    # Core variant: AI + Search only, no webform bloat
    composer require -n --no-update \
        cweagans/composer-patches:^2@beta \
        drupal/ai_provider_litellm:@beta \
        drupal/search_api \
        drupal/search_api_db
fi
