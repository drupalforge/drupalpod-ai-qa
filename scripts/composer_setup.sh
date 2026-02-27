#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Setup Composer Project from CMS/Core Template.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This script creates a new Drupal project (CMS or Core), configures it,
# and adds AI modules as path repositories.
# It intentionally consumes resolver output (manifest) instead of deciding
# compatibility again, so install and resolve stay in sync.

# Load common utilities.
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/lib/bootstrap.sh"

cd "$COMPOSER_ROOT"

# Determine which starter template to use.
# Options: "cms" or "core"
STARTER_TEMPLATE="${DP_STARTER_TEMPLATE:-cms}"
if [ "$STARTER_TEMPLATE" != "cms" ] && [ "$STARTER_TEMPLATE" != "core" ]; then
    echo "ERROR: Unsupported DP_STARTER_TEMPLATE: $STARTER_TEMPLATE (expected cms or core)." >&2
    exit 1
fi

# Resolve composer project + version constraint in one place.
COMPOSER_PROJECT=""
INSTALL_VERSION=""

if [ "$STARTER_TEMPLATE" = "cms" ]; then
    COMPOSER_PROJECT="drupal/cms"
else
    COMPOSER_PROJECT="drupal/recommended-project"
fi

if [ -n "${DP_VERSION:-}" ]; then
    # User specified explicit version
    INSTALL_VERSION="$(normalize_version_to_composer "${DP_VERSION}")"
else
    # Auto-detect: use exact version resolved by resolve_modules.sh.
    if [ -f "$MANIFEST_FILE" ]; then
        if [ "$STARTER_TEMPLATE" = "cms" ]; then
            # For CMS, use resolved CMS version if available
            RESOLVED_VERSION=$(jq -r '.resolved_cms_version // ""' "$MANIFEST_FILE")
        else
            # For Core, use resolved core version if available
            RESOLVED_VERSION=$(jq -r '.resolved_core_version // ""' "$MANIFEST_FILE")
        fi

        if [ -n "$RESOLVED_VERSION" ] && [ "$RESOLVED_VERSION" != "null" ] && [[ "$RESOLVED_VERSION" != *no-version-set* ]]; then
            INSTALL_VERSION="$RESOLVED_VERSION"
            log_info "Using auto-detected version from manifest: $INSTALL_VERSION"
        fi
    fi
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
    time composer create-project --no-plugins --prefer-dist -n --no-install "$COMPOSER_PROJECT":"$INSTALL_VERSION" temp-composer-files
else
    # No version specified and no manifest - use latest
    time composer create-project --no-plugins --prefer-dist -n --no-install "$COMPOSER_PROJECT" temp-composer-files
fi

# Copy all files (including hidden files) from temp to docroot.
cp -r temp-composer-files/. .

# Clean up temp directory.
rm -rf temp-composer-files

# Programmatically fix Composer 2.2 allow-plugins to avoid errors.
# IMPORTANT: Do this first so later Composer commands can execute non-interactively.
ALLOWED_PLUGINS=(
    "composer/installers:true"
    "drupal/core-project-message:true"
    "drupal/core-vendor-hardening:true"
    "drupal/core-composer-scaffold:true"
    "drupal/site_template_helper:true"
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

# Configure lenient mode only when resolver explicitly provided a package list.
if [ "${DP_FORCE_DEPENDENCIES}" = "1" ] && [ -n "${DP_LENIENT_PACKAGES:-}" ]; then
    IFS=',' read -ra LENIENT_PACKAGES <<< "$DP_LENIENT_PACKAGES"
    configure_lenient_mode "${LENIENT_PACKAGES[@]}"
fi

# Scaffold settings.php.
composer config --json extra.drupal-scaffold.file-mapping '{"[web-root]/sites/default/settings.php":{"path":"web/core/assets/scaffold/files/default.settings.php","overwrite":false}}'
composer config scripts.post-drupal-scaffold-cmd \
    "cd web/sites/default && test -z \"\$(grep 'include \\\$devpanel_settings;' settings.php)\" && patch -Np1 -r /dev/null < \"$PROJECT_ROOT/.devpanel/drupal-settings.patch\" || :"

# Enable the local AI lenient plugin only when lenient package list is set.
if [ "${DP_FORCE_DEPENDENCIES}" = "1" ] && [ -n "${DP_LENIENT_PACKAGES:-}" ]; then
    plugin_path="$PROJECT_ROOT/src/ai-lenient-plugin"
    if [ -d "$plugin_path" ]; then
        composer config --no-plugins repositories.ai-lenient-plugin \
            "{\"type\": \"path\", \"url\": \"$plugin_path\", \"options\": {\"symlink\": true}}"
        composer require --prefer-dist -n --no-progress "drupalpod/ai-lenient-plugin:*@dev"

        # Ensure lenient plugins are installed/active before the main solve.
        # Without this warm-up step, the first full update can run before
        # plugin constraint rewriting takes effect for forced combinations.
        composer -n update --no-progress \
            mglaman/composer-drupal-lenient \
            drupalpod/ai-lenient-plugin
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI MODULES FROM GIT (Path Repositories)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Add path repositories only for modules marked compatible in the manifest.
# skipped/incompatible modules are cloned for convenience but not required here.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ -n "${COMPATIBLE_MODULES:-}" ]; then
    echo "Adding path repositories for AI modules..."

    # Batch all require operations into a single composer invocation to avoid
    # repeated composer.json read/write cycles (each require call locks, parses,
    # modifies, validates, and writes composer.json separately).
    declare -a require_args=()

    IFS=',' read -ra MODULES <<< "$COMPATIBLE_MODULES"
    for module in "${MODULES[@]}"; do
        module="${module// /}"

        if [ -z "$module" ]; then
            continue
        fi

        repo_path="$PROJECT_ROOT/repos/$module"
        if [ -d "$repo_path" ]; then
            echo "  - Adding path repository for: $module"
            composer config --no-plugins repositories."$module"-git \
                "{\"type\": \"path\", \"url\": \"$repo_path\", \"options\": {\"symlink\": true}}"

            require_args+=("drupal/$module:*@dev")
        fi
    done

    if [ "${#require_args[@]}" -gt 0 ]; then
        composer require --prefer-dist -n --no-update "${require_args[@]}"
    fi

    echo "Path repositories added for AI modules!"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI DEPENDENCIES
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

if [ "$STARTER_TEMPLATE" = "cms" ]; then
    echo "Using CMS dependencies from drupal/cms template..."

else
    echo "Adding Core AI dependencies..."

    # Core variant: Search only - AI modules come from git via path repos.
    # Core template does not include drush by default, so we add it here.
    composer require --prefer-dist -n --no-update \
        drush/drush \
        drupal/search_api \
        drupal/search_api_db \
        drupal/token
fi
