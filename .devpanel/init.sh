#!/usr/bin/env bash
set -eu -o pipefail

# Initialize all variables with null if they do not exist
: "${DEBUG_SCRIPT:=}"
: "${DP_INSTALL_PROFILE:=}"
: "${DP_EXTRA_DEVEL:=}"
: "${DP_EXTRA_ADMIN_TOOLBAR:=}"
: "${DP_PROJECT_TYPE:=}"
: "${DP_STARTER_TEMPLATE:=}"
: "${DEVEL_NAME:=}"
: "${DEVEL_PACKAGE:=}"
: "${ADMIN_TOOLBAR_NAME:=}"
: "${ADMIN_TOOLBAR_PACKAGE:=}"
: "${COMPOSER_DRUPAL_LENIENT:=}"
: "${DP_CORE_VERSION:=}"
: "${DP_ISSUE_BRANCH:=}"
: "${DP_ISSUE_FORK:=}"
: "${DP_MODULE_VERSION:=}"
: "${DP_PATCH_FILE:=}"

# Assuming .sh files are in the same directory as this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -n "$DEBUG_SCRIPT" ]; then
    set -x
fi

convert_version() {
    local version=$1
    if [[ $version =~ "-" ]]; then
        # Remove the part after the dash and replace the last numeric segment with 'x'
        local base_version=${version%-*}
        echo "${base_version%.*}.x"
    else
        echo "$version"
    fi
}

# Test cases
# echo $(convert_version "9.2.5-dev1")    # Output: 9.2.x
# echo $(convert_version "9.2.5")         # Output: 9.2.5
# echo $(convert_version "10.1.0-beta1")  # Output: 10.1.x
# echo $(convert_version "11.0-dev")      # Output: 11.x

# Set a default setup if project type wasn't specified
if [ -z "$DP_PROJECT_TYPE" ]; then
    source "$DIR/fallback_setup.sh"
fi

source "$DIR/git_setup.sh"

# If this is an issue fork of Drupal core - set the drupal core version based on that issue fork
if [ "$DP_PROJECT_TYPE" == "project_core" ] && [ -n "$DP_ISSUE_FORK" ]; then
    VERSION_FROM_GIT=$(grep 'const VERSION' "${APP_ROOT}"/repos/drupal/core/lib/Drupal.php | awk -F "'" '{print $2}')
    DP_CORE_VERSION=$(convert_version "$VERSION_FROM_GIT")
    export DP_CORE_VERSION
fi

# Measure the time it takes to go through the script
script_start_time=$(date +%s)

# Remove root-owned files.
sudo rm -rf $APP_ROOT/lost+found

source "$DIR/contrib_modules_setup.sh"
source "$DIR/cleanup.sh"
source "$DIR/composer_setup.sh"

if [ -n "$DP_PATCH_FILE" ]; then
    echo Applying selected patch "$DP_PATCH_FILE"
    cd "${WORK_DIR}" && curl "$DP_PATCH_FILE" | patch -p1
fi

# Prepare special setup to work with Drupal core
if [ "$DP_PROJECT_TYPE" == "project_core" ]; then
    source "$DIR/drupal_setup_core.sh"
# Prepare special setup to work with Drupal contrib
elif [ -n "$DP_PROJECT_NAME" ]; then
    source "$DIR/drupal_setup_contrib.sh"
fi

time "${DIR}"/install-essential-packages.sh
# Configure phpcs for drupal.
cd "$APP_ROOT" &&
    vendor/bin/phpcs --config-set installed_paths vendor/drupal/coder/coder_sniffer

if [ -z "$(drush status --field=db-status)" ] || \
   [ $DP_INSTALL_PROFILE != 'demo_umami' ] || \
   ! printf "11.2.2\n$DP_CORE_VERSION" | sort -C; then
    # New site install, different install profile, or lower core version.
    time drush -n si --account-pass=admin --site-name="DrupalPod" "$DP_INSTALL_PROFILE"
elif [ $DP_CORE_VERSION != '11.2.2' ]; then
    # Run database updates if the core version is different.
    time drush -n updb
fi

# Install devel and admin_toolbar modules.
if [ "$DP_EXTRA_DEVEL" != '1' ]; then
    DEVEL_NAME=
fi
if [ "$DP_EXTRA_ADMIN_TOOLBAR" != '1' ]; then
    ADMIN_TOOLBAR_NAME=
fi

# Enable extra modules.
cd "${APP_ROOT}" &&
    drush en -y \
        $ADMIN_TOOLBAR_NAME \
        $DEVEL_NAME

# Enable the requested module.
if [ "$DP_PROJECT_TYPE" == "project_module" ]; then
    cd "${APP_ROOT}" && drush en -y "$DP_PROJECT_NAME"
fi

# Enable the requested theme.
if [ "$DP_PROJECT_TYPE" == "project_theme" ]; then
    cd "${APP_ROOT}" && drush then -y "$DP_PROJECT_NAME"
    cd "${APP_ROOT}" && drush config-set -y system.theme default "$DP_PROJECT_NAME"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI SETUP
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Enable AI base modules (ready for configuration)
cd "${APP_ROOT}" && drush en -y ai ai_provider_litellm

# If API key is provided via environment variable, auto-configure AI
if [ -n "${DP_AI_VIRTUAL_KEY:-}" ]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🤖 Auto-configuring AI provider..."
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Save API key
    drush -n key-save litellm_api_key --label="LiteLLM API key" --key-provider=env --key-provider-settings='{
        "env_variable": "DP_AI_VIRTUAL_KEY",
        "base64_encoded": false,
        "strip_line_breaks": true
    }'

    # Configure LiteLLM provider
    drush -n cset ai_provider_litellm.settings api_key litellm_api_key
    drush -n cset ai_provider_litellm.settings moderation false --input-format yaml
    drush -n cset ai_provider_litellm.settings host "${DP_AI_HOST:="https://ai.drupalforge.org"}"

    # CMS: Apply recipe and configure all providers
    if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
        echo "Applying Drupal CMS AI recipe..."
        drush -q recipe ../recipes/drupal_cms_ai --input=drupal_cms_ai.provider=litellm

        # Configure all AI providers for production use
        drush -n cset ai.settings default_providers.chat.provider_id litellm
        drush -n cset ai.settings default_providers.chat.model_id openai/gpt-4o-mini
        drush -n cset ai.settings default_providers.chat_with_complex_json.provider_id litellm
        drush -n cset ai.settings default_providers.chat_with_complex_json.model_id openai/gpt-4o-mini
        drush -n cset ai.settings default_providers.chat_with_image_vision.provider_id litellm
        drush -n cset ai.settings default_providers.chat_with_image_vision.model_id openai/gpt-4o-mini
        drush -n cset ai.settings default_providers.chat_with_structured_response.provider_id litellm
        drush -n cset ai.settings default_providers.chat_with_structured_response.model_id openai/gpt-4o-mini
        drush -n cset ai.settings default_providers.chat_with_tools.provider_id litellm
        drush -n cset ai.settings default_providers.chat_with_tools.model_id openai/gpt-4o-mini
        drush -n cset ai.settings default_providers.embeddings.provider_id litellm
        drush -n cset ai.settings default_providers.embeddings.model_id openai/text-embedding-3-small
        drush -n cset ai.settings default_providers.text_to_speech.provider_id litellm
        drush -n cset ai.settings default_providers.text_to_speech.model_id openai/gpt-4o-mini-realtime-preview
        drush -n cset ai_assistant_api.ai_assistant.drupal_cms_assistant llm_provider __default__
        drush -n cset klaro.klaro_app.deepchat status 0

        echo "✅ AI configured for Drupal CMS"
    else
        # Core: Just configure embeddings for AI Search
        echo "Configuring AI Search for Core variant..."
        drush -n cset ai.settings default_providers.embeddings.provider_id litellm
        drush -n cset ai.settings default_providers.embeddings.model_id openai/text-embedding-3-small

        echo "✅ AI configured for AI Search"
    fi

    # Configure Automatic Updates to trust patches
    drush -n cset --input-format=yaml package_manager.settings additional_trusted_composer_plugins '["cweagans/composer-patches"]'
    drush -n cset --input-format=yaml package_manager.settings additional_known_files_in_project_root '["patches.json", "patches.lock.json"]'
else
    # AI modules installed but not configured - display instructions
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "🤖 AI Modules Ready (Not Configured)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo ""
    echo "AI modules installed: ✓ ai, ✓ ai_provider_litellm"
    if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
        echo "PostgreSQL + pgvector: ✓ Ready for AI Search"
    else
        echo "PostgreSQL + pgvector: ✓ Ready for AI Search"
        echo "Search API: ✓ Available for semantic search"
    fi
    echo ""
    echo "To enable AI features:"
    echo "  1. Get API key from: https://ai.drupalforge.org"
    echo "  2. Run: ddev setup-ai"
    echo "     OR set env var: export DP_AI_VIRTUAL_KEY=sk-your-key"
    echo ""
    echo "QA Tip: Test AI Search performance with PostgreSQL + pgvector!"
    echo ""
fi

# Finish measuring script time.
script_end_time=$(date +%s)
runtime=$((script_end_time - script_start_time))
echo "init.sh script ran for" $runtime "seconds"
