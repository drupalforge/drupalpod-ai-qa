# DrupalPod AI QA

Provides temporary AI provider key setup for QA environments.

## Purpose

This module allows QA testers to temporarily configure AI providers (OpenAI, Anthropic) with their own API keys for testing purposes. Keys expire automatically (configurable via `AiQaProviderManager::TTL`) and are stored using Easy Encryption.

## Features

- **Temporary API Keys**: Keys expire automatically after a configurable duration (see AiQaProviderManager::TTL constant)
- **Encrypted Storage**: Uses Easy Encryption for secure key storage
- **Auto-Redirect**: Authenticated users with appropriate permissions are automatically prompted to enter a key
- **Multiple Provider Support**: Currently supports OpenAI and Anthropic (Claude)
- **Provider Aliases**: Accepts common aliases (e.g., 'claude' → 'anthropic')
- **Automatic Cache Clearing**: Clears provider caches when keys change

## Installation

1. Enable the module:
   ```bash
   drush en drupalpod_ai_qa
   ```

2. Enable an AI provider module (e.g., `ai_provider_openai` or `ai_provider_anthropic`)

3. Ensure `easy_encryption` is enabled for encrypted key storage:
   ```bash
   drush en easy_encryption
   ```

4. Pre-configure the provider via code or configuration (see Configuration section)

5. Users with "administer ai providers" permission will be automatically prompted to enter a temporary API key

## Configuration

### Via Code

```php
/** @var \Drupal\drupalpod_ai_qa\AiQaProviderManager $providerManager */
$providerManager = \Drupal::service('drupalpod_ai_qa.provider_manager');

// Apply OpenAI as the QA provider
$providerManager->applyProvider('openai');

// Or use Anthropic (also accepts 'claude' as an alias)
$providerManager->applyProvider('anthropic');
```

### Via Configuration

Edit `config/drupalpod_ai_qa.settings.yml`:

```yaml
selected_provider: 'openai'
```

## Security Considerations

### Important Warnings

- **QA Environments Only**: This module is designed for QA/testing environments, NOT production
- **Temporary Storage**: API keys are stored temporarily and expire automatically (configurable TTL)
- **Encrypted Storage Required**: Keys are stored using Easy Encryption
- **Access Control**: Only users with "administer ai providers" permission can enter keys

### Security Features

- CSRF protection via Drupal Form API
- Input validation (character set, minimum length)
- Automatic key expiry and purging
- Encrypted key storage via Easy Encryption
- Logging of provider configuration errors

## How It Works

### Workflow

1. **Provider Configuration**: An administrator pre-configures a provider (OpenAI, Anthropic)
2. **Key Prompt**: Users with "administer ai providers" permission are redirected to enter an API key
3. **Key Storage**: The key is stored in a managed Key entity with automatic expiry
4. **Provider Setup**: The provider module is configured to use the managed key
5. **Automatic Expiry**: After the TTL expires, the key is purged and users are prompted again

### Components

- **AiQaProviderManager** (Service): Core business logic for provider management
- **AiQaApiKeyForm** (Form): Collects the temporary API key from users
- **AiKeyPromptSubscriber** (Event Subscriber): Redirects users to the key form when needed
- **KeyExpirySubscriber** (Event Subscriber): Purges expired keys on each request

## API

### Service: `drupalpod_ai_qa.provider_manager`

```php
// Get the service
$providerManager = \Drupal::service('drupalpod_ai_qa.provider_manager');

// Apply a provider
$providerManager->applyProvider('openai');

// Store a temporary key
$providerManager->storeTemporaryKey('sk-...');

// Check if a usable key exists
$hasKey = $providerManager->hasUsableKey();

// Get the selected provider ID
$providerId = $providerManager->getSelectedProviderId(); // 'openai' or 'anthropic'

// Get the provider label
$label = $providerManager->getSelectedProviderLabel(); // 'OpenAI' or 'Anthropic'

// Get key expiry timestamp
$expiry = $providerManager->getKeyExpiry();

// Reset provider selection
$providerManager->resetProviderSelection();
```

## Testing

### Running Tests

```bash
# Run all tests
./vendor/bin/phpunit modules/custom/drupalpod_ai_qa

# Run kernel tests
./vendor/bin/phpunit modules/custom/drupalpod_ai_qa/tests/src/Kernel
```

### Test Coverage

Current test coverage includes:
- Provider application and key entity creation
- Default model configuration
- Key expiry and purging

### Future Test Additions

Consider adding tests for:
- Provider alias normalization
- Reset provider selection
- Easy Encryption key storage behavior
- Form validation
- Event subscriber behavior

## Supported Providers

### OpenAI

- **Module**: `ai_provider_openai`
- **Aliases**: 'openai'
- **Key Format**: `sk-...` (validated to be 20+ characters)

### Anthropic

- **Module**: `ai_provider_anthropic`
- **Aliases**: 'anthropic', 'claude'
- **Key Format**: alphanumeric with dashes/underscores (validated to be 20+ characters)

## Architecture

### Design Principles

- **Service-Oriented**: Core logic in a reusable service
- **Dependency Injection**: All dependencies properly injected
- **PHP 8.2+ Features**: Constructor property promotion, typed properties, readonly
- **Modern Drupal**: Uses attributes, not annotations
- **Event-Driven**: Uses event subscribers instead of hooks
- **Configuration Management**: Full config schema support

### Key Design Decisions

1. **Key Module Integration**: Uses the Key module for secure, managed key storage
2. **State for Expiry**: Uses State API for expiry timestamp (not exportable)
3. **Static Caching**: Caches selected provider ID to reduce config reads
4. **Encrypted Key Storage**: Stores managed QA keys with Easy Encryption
5. **Cache Clearing**: Aggressive cache clearing to ensure fresh data after key changes

## Extending

### Adding New Providers

Edit `AiQaProviderManager::$providers` and `AiQaProviderManager::$aliases`:

```php
private array $providers = [
  'newprovider' => [
    'label' => 'New Provider',
    'module' => 'ai_provider_newprovider',
    'config_name' => 'ai_provider_newprovider.settings',
    'config_key' => 'api_key',
    'key_id' => 'drupalpod_ai_qa_newprovider',
    'key_label' => 'DrupalPod QA New Provider API key',
  ],
];

private array $aliases = [
  'newprovider' => 'newprovider',
  'np' => 'newprovider', // Optional alias
];
```

## Troubleshooting

### Keys Not Persisting

- Verify `easy_encryption` is enabled
- Verify the Key module is installed
- Check permissions on the key storage location

### Redirect Loop

- Verify the route 'drupalpod_ai_qa.api_key_form' is in allowed routes
- Check if the user has "administer ai providers" permission
- Ensure the key expiry hasn't passed

### Provider Not Working

- Verify the provider module is enabled
- Check that `applyProvider()` returned TRUE
- Review watchdog logs for errors
- Ensure the key value was actually stored

## Logging

The module logs errors to the 'drupalpod_ai_qa' channel:

```bash
# View logs
drush watchdog:show --type=drupalpod_ai_qa
```

Common log messages:
- Invalid provider errors
- Provider module not installed errors

## Related Modules

- [AI](https://drupal.org/project/ai) - Core AI framework
- [Key](https://drupal.org/project/key) - Secure key storage
- [Easy Encryption](https://drupal.org/project/easy_encryption) - Key encryption

## Development

### Code Quality

The module follows Drupal coding standards:

```bash
# Run PHPCS
./vendor/bin/phpcs --standard=Drupal,DrupalPractice modules/custom/drupalpod_ai_qa

# Run PHPStan
./vendor/bin/phpstan analyze modules/custom/drupalpod_ai_qa
```

### Contributing

When contributing:
1. Follow PHP 8.2+ features and best practices
2. Add comprehensive PHPDoc comments
3. Use dependency injection (no static service calls)
4. Include tests for new functionality
5. Update this README for significant changes

## License

This module is licensed under the GPL-2.0-or-later license.

## Maintainers

- Current development is part of DrupalPod AI QA testing infrastructure

## Version History

See the CHANGELOG.md file for version history and release notes.
