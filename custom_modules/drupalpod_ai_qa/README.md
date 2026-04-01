# DrupalPod AI QA

Provides temporary AI provider key setup for QA environments.

## Purpose

This module allows QA testers to temporarily configure an AI provider with their own API key for testing purposes. The key is stored in a single managed key entity (`drupalpod_ai_qa`) shared across all providers. It expires automatically after 4 hours and is stored using Easy Encryption.

Providers with their own native provisioning flow (e.g. amazee.ai) are supported without key management — the module sets them as the default provider and steps aside.

## Features

- **Single managed key**: One key entity (`drupalpod_ai_qa`) used regardless of provider
- **Provider-agnostic prompt**: Prompts show the current default provider name, not a hardcoded provider
- **Native key support**: Providers like amazee.ai that have their own key/provisioning flow bypass the key prompt entirely
- **Temporary keys**: Keys expire automatically after 4 hours
- **Encrypted storage**: Uses Easy Encryption for secure key storage
- **Auto-redirect**: Authenticated users with appropriate permissions are automatically prompted to enter a key when needed
- **Provider aliases**: Accepts common aliases (e.g., `'claude'` → `'anthropic'`, `'amazee'` → `'amazeeai'`)
- **Automatic cache clearing**: Clears provider caches when keys change

## Installation

1. Enable the module:
   ```bash
   drush en drupalpod_ai_qa
   ```

2. Enable an AI provider module (e.g., `ai_provider_openai`, `ai_provider_anthropic`, or `ai_provider_amazeeio`)

3. Pre-configure the provider (see Configuration section)

4. Users with "administer ai providers" permission will be automatically prompted to enter a temporary API key (unless the provider uses a native key flow)

## Configuration

### Via Code

```php
/** @var \Drupal\drupalpod_ai_qa\AiQaProviderManager $providerManager */
$providerManager = \Drupal::service('drupalpod_ai_qa.provider_manager');

// Apply a provider — sets it as default and configures the managed key
$providerManager->applyProvider('openai');
$providerManager->applyProvider('anthropic'); // also accepts 'claude'
$providerManager->applyProvider('amazeeai');  // also accepts 'amazee', 'amazeeio'
```

## Supported Providers

### OpenAI
- **Module**: `ai_provider_openai`
- **Aliases**: `openai`
- **Key management**: managed key (`drupalpod_ai_qa`), expires after TTL

### Anthropic
- **Module**: `ai_provider_anthropic`
- **Aliases**: `anthropic`, `claude`
- **Key management**: managed key (`drupalpod_ai_qa`), expires after TTL

### amazee.ai
- **Module**: `ai_provider_amazeeio`
- **Aliases**: `amazeeai`, `amazee`, `amazeeio`
- **Key management**: native — if the provider already has a key configured (e.g. from a recipe), the managed key flow is skipped entirely and the key never expires

## Security Considerations

- **QA environments only**: Not designed for production use
- **Temporary storage**: API keys expire automatically (configurable TTL)
- **Encrypted storage**: Keys stored via Easy Encryption
- **Access control**: Only users with "administer ai providers" permission can enter keys
- CSRF protection via Drupal Form API

## How It Works

1. **Provider configuration**: `applyProvider()` points the provider `api_key` config at the `drupalpod_ai_qa` key entity and configures `ai.settings` default providers
2. **Key prompt**: Users are redirected to enter a key when a provider is configured to use the QA key and none is present
3. **Key storage**: The key is stored in the single `drupalpod_ai_qa` key entity
4. **Automatic expiry**: After the TTL expires, the key is purged and users are prompted again

## Extending

### Adding New Providers

To add a provider, modify `AiQaProviderManager` directly: add an entry to the `$providers` array in the constructor using `buildProviderDefinition()`, and add any aliases to `$aliases`.

Providers that have their own provisioning flow (e.g. amazee.ai) require no special handling — the module automatically detects whether the provider's config already points at its own key and skips the key prompt in that case.

## Troubleshooting

### Keys Not Persisting
- Verify `easy_encryption` is enabled
- Verify the Key module is installed
- Check permissions on the key storage location

### Redirect Loop
- Verify the route `drupalpod_ai_qa.api_key_form` is in allowed routes
- Check user has "administer ai providers" permission

### amazee.ai Not Detected as Having a Key
- Check `ai_provider_amazeeio.settings.api_key` has a non-empty value in config
- This is set by the `drupal_cms_ai` recipe with `provider=amazeeio`

### Provider Not Working
- Verify the provider module is enabled
- Check that `applyProvider()` returned TRUE
- Review watchdog logs: `drush watchdog:show --type=drupalpod_ai_qa`

## Related Modules

- [AI](https://drupal.org/project/ai) — Core AI framework
- [Key](https://drupal.org/project/key) — Secure key storage
- [Easy Encryption](https://drupal.org/project/easy_encryption) — Key encryption
