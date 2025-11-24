#!/usr/bin/env bash
if [ -n "${DEBUG_SCRIPT:-}" ]; then
  set -x
fi
set -eu -o pipefail
cd $APP_ROOT

mkdir -p logs
LOG_FILE="logs/init-$(date +%F-%T).log"
exec > >(tee $LOG_FILE) 2>&1

TIMEFORMAT=%lR
# For faster performance, don't audit dependencies automatically.
export COMPOSER_NO_AUDIT=1
# For faster performance, don't install dev dependencies.
export COMPOSER_NO_DEV=1

# Assuming .sh files are in the same directory as this script
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Always source fallback_setup to set all defaults
# This ensures DP_INSTALL_PROFILE and other variables are initialized
source "$DIR/fallback_setup.sh"

# Install VSCode Extensions
if [ -n "${DP_VSCODE_EXTENSIONS:-}" ]; then
  IFS=','
  for value in $DP_VSCODE_EXTENSIONS; do
    time code-server --install-extension $value
  done
fi

#== Clean rebuild if requested.
if [ "${DP_REBUILD:-0}" = "1" ]; then
  echo
  echo 'Performing clean rebuild...'
  echo 'Removing vendor and web directories...'
  time rm -rf vendor web/core web/modules/contrib web/themes/contrib web/profiles/contrib composer.lock
  echo 'Rebuild mode enabled.'
  echo
fi

#== Remove root-owned files.
echo
echo Remove root-owned files.
time sudo rm -rf lost+found

#== Composer install.
echo
if [ "${DP_REBUILD:-0}" = "1" ] || [ ! -f composer.json ]; then
  echo 'Generate composer.json.'
  time source .devpanel/composer_setup.sh
  echo
elif [ -f composer.json ]; then
  if composer show --locked cweagans/composer-patches ^2 &> /dev/null; then
    echo 'Update patches.lock.json.'
    time composer prl
    echo
  fi
fi
echo 'Running composer update...'
time composer -n update --no-dev --no-progress || { echo "Composer update failed!"; exit 1; }

#== Create the private files directory.
if [ ! -d private ]; then
  echo
  echo 'Create the private files directory.'
  time mkdir private
fi

#== Create the config sync directory.
if [ ! -d config/sync ]; then
  echo
  echo 'Create the config sync directory.'
  time mkdir -p config/sync
fi

#== Generate hash salt.
if [ ! -f .devpanel/salt.txt ]; then
  echo
  echo 'Generate hash salt.'
  time openssl rand -hex 32 > .devpanel/salt.txt
fi

#== Install Drupal.
echo
if [ "${DP_REBUILD:-0}" = "1" ] || ! drush status --field=bootstrap | grep -q "Drupal bootstrap"; then
  if [ -z "$DP_INSTALL_PROFILE" ]; then
    echo 'Install Drupal.'
    time drush -n si
  else
    echo 'Install Drupal with profile: '"$DP_INSTALL_PROFILE"
    time drush -n si "$DP_INSTALL_PROFILE"
  fi

  #== Apply the AI recipe.
  if [ -n "${DP_AI_VIRTUAL_KEY:-}" ]; then
    echo
    time drush -n en ai_provider_litellm
    drush -n key-save litellm_api_key --label="LiteLLM API key" --key-provider=env --key-provider-settings='{
      "env_variable": "DP_AI_VIRTUAL_KEY",
      "base64_encoded": false,
      "strip_line_breaks": true
    }'
    drush -n cset ai_provider_litellm.settings api_key litellm_api_key
    drush -n cset ai_provider_litellm.settings moderation false --input-format yaml
    drush -n cset ai_provider_litellm.settings host "${DP_AI_HOST:="https://ai.drupalforge.org"}"
    drush -q recipe ../recipes/drupal_cms_ai --input=drupal_cms_ai.provider=litellm
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
  fi

  echo
  echo 'Tell Automatic Updates about patches.'
  drush -n cset --input-format=yaml package_manager.settings additional_trusted_composer_plugins '["cweagans/composer-patches"]'
  drush -n cset --input-format=yaml package_manager.settings additional_known_files_in_project_root '["patches.json", "patches.lock.json"]'
  time drush ev '\Drupal::moduleHandler()->invoke("automatic_updates", "modules_installed", [[], FALSE])'
else
  echo 'Update database.'
  time drush -n updb
fi

#== Warm up caches.
echo
echo 'Run cron.'
time drush cron
echo
echo 'Populate caches.'
time drush cache:warm
time .devpanel/warm

#== Finish measuring script time.
INIT_DURATION=$SECONDS
INIT_HOURS=$(($INIT_DURATION / 3600))
INIT_MINUTES=$(($INIT_DURATION % 3600 / 60))
INIT_SECONDS=$(($INIT_DURATION % 60))
printf "\nTotal elapsed time: %d:%02d:%02d\n" $INIT_HOURS $INIT_MINUTES $INIT_SECONDS
