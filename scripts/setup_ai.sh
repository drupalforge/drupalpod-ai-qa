#!/usr/bin/env bash
set -eu -o pipefail

echo

if [ -n "${DP_AI_PROVIDER:-}" ]; then
  case "${DP_AI_PROVIDER}" in
    openai)
      provider_module="ai_provider_openai"
      qa_provider="openai"
      ;;
    claude|anthropic)
      provider_module="ai_provider_anthropic"
      qa_provider="anthropic"
      ;;
    amazee|amazeeai|amazeeio)
      provider_module="ai_provider_amazeeio"
      qa_provider=""
      ;;
    *)
      echo "Unsupported DP_AI_PROVIDER value: ${DP_AI_PROVIDER}"
      exit 1
      ;;
  esac

  time $DRUSH -n en "${provider_module}" drupalpod_ai_qa

  if [ -n "${qa_provider}" ]; then
    # For QA-managed providers, install only what we need and let the custom
    # module handle provider defaults plus API key prompting.
    $DRUSH -n php:eval "\Drupal::service('drupalpod_ai_qa.provider_manager')->applyProvider('${qa_provider}');"
  else
    # amazee.ai already has a native onboarding/provisioning flow, so keep
    # using the recipe path rather than the DrupalPod QA key prompt flow.
    $DRUSH -q recipe ../recipes/drupal_cms_ai --input=drupal_cms_ai.provider=amazeeio
    $DRUSH -n php:eval "\Drupal::service('drupalpod_ai_qa.provider_manager')->resetProviderSelection();"
  fi

  return 0
fi

time $DRUSH -n en ai_provider_litellm drupalpod_ai_qa
$DRUSH -n key-save litellm_api_key --label="LiteLLM API key" --key-provider=env --key-provider-settings='{
  "env_variable": "DP_AI_VIRTUAL_KEY",
  "base64_encoded": false,
  "strip_line_breaks": true
}'
$DRUSH -n cset ai_provider_litellm.settings api_key litellm_api_key
$DRUSH -n cset ai_provider_litellm.settings moderation false --input-format yaml
$DRUSH -n cset ai_provider_litellm.settings host "${DP_AI_HOST:="https://ai.drupalforge.org"}"
$DRUSH -q recipe ../recipes/drupal_cms_ai --input=drupal_cms_ai.provider=litellm
$DRUSH -n cset ai.settings default_providers.chat.provider_id litellm
$DRUSH -n cset ai.settings default_providers.chat.model_id openai/gpt-4o-mini
$DRUSH -n cset ai.settings default_providers.chat_with_complex_json.provider_id litellm
$DRUSH -n cset ai.settings default_providers.chat_with_complex_json.model_id openai/gpt-4o-mini
$DRUSH -n cset ai.settings default_providers.chat_with_image_vision.provider_id litellm
$DRUSH -n cset ai.settings default_providers.chat_with_image_vision.model_id openai/gpt-4o-mini
$DRUSH -n cset ai.settings default_providers.chat_with_structured_response.provider_id litellm
$DRUSH -n cset ai.settings default_providers.chat_with_structured_response.model_id openai/gpt-4o-mini
$DRUSH -n cset ai.settings default_providers.chat_with_tools.provider_id litellm
$DRUSH -n cset ai.settings default_providers.chat_with_tools.model_id openai/gpt-4o-mini
$DRUSH -n cset ai.settings default_providers.embeddings.provider_id litellm
$DRUSH -n cset ai.settings default_providers.embeddings.model_id openai/text-embedding-3-small
$DRUSH -n cset ai.settings default_providers.text_to_speech.provider_id litellm
$DRUSH -n cset ai.settings default_providers.text_to_speech.model_id openai/gpt-4o-mini-realtime-preview
$DRUSH -n cset ai_assistant_api.ai_assistant.drupal_cms_assistant llm_provider __default__
$DRUSH -n cset klaro.klaro_app.deepchat status 0
