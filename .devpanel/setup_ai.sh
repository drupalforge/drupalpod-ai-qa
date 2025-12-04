#!/usr/bin/env bash
set -eu -o pipefail


echo
time $DRUSH -n en ai_provider_litellm
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