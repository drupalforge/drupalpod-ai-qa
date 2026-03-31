<?php

declare(strict_types=1);

namespace Drupal\drupalpod_ai_qa;

use Drupal\ai\AiProviderPluginManager;
use Drupal\Component\Datetime\TimeInterface;
use Drupal\Core\Config\ConfigFactoryInterface;
use Drupal\Core\Entity\EntityTypeManagerInterface;
use Drupal\Core\Extension\ModuleHandlerInterface;
use Drupal\Core\Logger\LoggerChannelFactoryInterface;
use Drupal\Core\State\StateInterface;
use Drupal\Core\Url;
use Drupal\key\KeyInterface;
use Drupal\key\Plugin\KeyProviderSettableValueInterface;

/**
 * Manages QA AI provider setup and temporary key storage.
 */
final class AiQaProviderManager {

  /**
   * The settings string.
   */
  private const SETTINGS = 'drupalpod_ai_qa.settings';

  /**
   * The expiry state key.
   */
  private const EXPIRY_STATE_KEY = 'drupalpod_ai_qa.key_expires_at';

  /**
   * Time-to-live for temporary keys in seconds.
   */
  private const TTL = 4 * 3600;

  /**
   * Provider definitions keyed by canonical provider ID.
   *
   * @var array<string, array<string, mixed>>
   */
  private array $providers;

  /**
   * Provider aliases keyed by normalized input.
   *
   * @var array<string, string>
   */
  private array $aliases = [
    'openai' => 'openai',
    'anthropic' => 'anthropic',
    'claude' => 'anthropic',
    'amazee' => 'amazeeai',
    'amazeeai' => 'amazeeai',
    'amazeeio' => 'amazeeai',
  ];

  /**
   * Static cache for the selected provider ID.
   */
  private ?string $selectedProviderId = NULL;

  /**
   * Whether the selected provider ID has been loaded.
   */
  private bool $selectedProviderIdLoaded = FALSE;

  /**
   * Per-request cache for hasUsableKey() result.
   */
  private ?bool $hasUsableKeyResult = NULL;

  public function __construct(
    private readonly ConfigFactoryInterface $configFactory,
    private readonly EntityTypeManagerInterface $entityTypeManager,
    private readonly StateInterface $state,
    private readonly TimeInterface $time,
    private readonly ModuleHandlerInterface $moduleHandler,
    private readonly AiProviderPluginManager $aiProviderManager,
    private readonly LoggerChannelFactoryInterface $loggerFactory,
  ) {
    $this->providers = [
      'openai' => $this->buildProviderDefinition('openai', 'OpenAI'),
      'anthropic' => $this->buildProviderDefinition('anthropic', 'Anthropic', [
        'extra_config' => [
          'openai_moderation' => FALSE,
        ],
      ]),
      'amazeeai' => $this->buildProviderDefinition('amazeeio', 'amazee.ai', [
        'provider_id' => 'amazeeai',
      ]),
    ];
  }

  /**
   * Normalizes a provider alias to a canonical provider ID.
   *
   * @param string|null $provider
   *   The provider ID or alias to normalize (e.g., 'OpenAI', 'claude').
   *
   * @return string|null
   *   The canonical provider ID, or NULL if invalid.
   */
  public function normalizeProvider(?string $provider): ?string {
    if ($provider === NULL || $provider === '') {
      return NULL;
    }

    $provider = strtolower(trim($provider));
    return $this->aliases[$provider] ?? NULL;
  }

  /**
   * Returns the currently configured provider definition.
   *
   * @return array<string, mixed>|null
   *   The provider definition, or NULL if none is configured.
   */
  public function getSelectedProviderDefinition(): ?array {
    $provider = $this->getSelectedProviderId();
    return $provider ? $this->providers[$provider] : NULL;
  }

  /**
   * Returns the canonical selected provider ID.
   *
   * @return string|null
   *   The canonical provider ID, or NULL if none is configured.
   */
  public function getSelectedProviderId(): ?string {
    if (!$this->selectedProviderIdLoaded) {
      $this->selectedProviderId = $this->normalizeProvider(
        $this->configFactory->get(self::SETTINGS)->get('selected_provider')
      );
      $this->selectedProviderIdLoaded = TRUE;
    }
    return $this->selectedProviderId;
  }

  /**
   * Applies QA defaults for the selected provider.
   *
   * This method:
   * - Sets the selected provider in configuration
   * - Creates or updates the managed key entity
   * - Configures the provider module to use the managed key
   * - Sets default models for AI operations
   * - Clears the expiry timestamp.
   *
   * @param string $provider
   *   The provider ID or alias (e.g., 'openai', 'anthropic', 'claude').
   *
   * @return bool
   *   TRUE if the provider was applied successfully, FALSE otherwise.
   */
  public function applyProvider(string $provider): bool {
    $provider = $this->normalizeProvider($provider);
    if ($provider === NULL) {
      $this->loggerFactory->get('drupalpod_ai_qa')->error('Invalid provider: @provider', ['@provider' => $provider]);
      return FALSE;
    }

    $definition = $this->providers[$provider];
    if (!$this->moduleHandler->moduleExists($definition['module'])) {
      $this->loggerFactory->get('drupalpod_ai_qa')->error('Provider module @module not installed for provider @provider', [
        '@module' => $definition['module'],
        '@provider' => $provider,
      ]);
      return FALSE;
    }

    // Reset static cache when provider changes.
    $this->selectedProviderIdLoaded = FALSE;
    $this->selectedProviderId = NULL;

    $this->clearManagedKeys();
    $this->configFactory->getEditable(self::SETTINGS)
      ->set('selected_provider', $provider)
      ->save();

    $this->ensureKeyEntity($provider);

    $setup_data = $this->getProviderSetupData($provider, $definition);

    $provider_config = $this->configFactory->getEditable($definition['config_name']);
    $provider_config->set($setup_data['key_config_name'] ?? $definition['config_key'], $definition['key_id']);
    foreach (($definition['extra_config'] ?? []) as $key => $value) {
      $provider_config->set($key, $value);
    }
    $provider_config->save();

    $defaults = [];
    foreach (($setup_data['default_models'] ?? []) as $operation => $model_id) {
      $defaults[$operation] = [
        'provider_id' => $provider,
        'model_id' => $model_id,
      ];
    }
    if ($defaults !== []) {
      $this->configFactory->getEditable('ai.settings')
        ->set('default_providers', $defaults)
        ->save();
    }

    // Ensure the Drupal CMS assistant uses the QA provider instead of
    // amazee.io.
    if ($this->moduleHandler->moduleExists('ai_assistant_api')) {
      $this->configFactory->getEditable('ai_assistant_api.ai_assistant.drupal_cms_assistant')
        ->set('llm_provider', '__default__')
        ->save();
    }

    $this->state->delete(self::EXPIRY_STATE_KEY);

    return TRUE;
  }

  /**
   * Stores a temporary API key for the configured provider.
   *
   * The key is stored in a managed key entity and will expire after the TTL
   * duration (see self::TTL constant).
   *
   * @param string $api_key
   *   The API key to store.
   */
  public function storeTemporaryKey(string $api_key): void {
    $provider = $this->getSelectedProviderId();
    if ($provider === NULL || $api_key === '') {
      return;
    }

    $key = $this->ensureKeyEntity($provider);
    $key->setKeyValue($api_key);
    $key->save();

    $this->resetProviderCaches($provider);
    $this->state->set(self::EXPIRY_STATE_KEY, $this->time->getRequestTime() + self::TTL);
    $this->hasUsableKeyResult = NULL;
  }

  /**
   * Validates a submitted API key against the selected provider.
   *
   * @param string $api_key
   *   The API key to validate.
   *
   * @return string|null
   *   A user-facing error message, or NULL if the key validates.
   */
  public function validateTemporaryKey(string $api_key): ?string {
    $provider = $this->getSelectedProviderId();
    if ($provider === NULL || $api_key === '') {
      return 'No AI provider is configured for this environment.';
    }

    try {
      $this->resetProviderCaches($provider);

      $provider_instance = $this->aiProviderManager->createInstance($provider);
      $provider_instance->setAuthentication($api_key);

      $host = $this->configFactory->get($this->providers[$provider]['config_name'])->get('host');
      if (is_string($host) && $host !== '') {
        $provider_instance->setConfiguration(['host' => $host]);
      }

      $models = $provider_instance->getConfiguredModels();
      if ($models === []) {
        return 'The API key could not be validated. Please double-check it and try again.';
      }
    }
    catch (\Throwable $exception) {
      $this->loggerFactory->get('drupalpod_ai_qa')->warning('Temporary AI key validation failed for provider @provider: @message', [
        '@provider' => $provider,
        '@message' => $exception->getMessage(),
      ]);
      return 'The API key could not be validated. Please double-check it and try again.';
    }

    return NULL;
  }

  /**
   * Returns TRUE when the current provider has a non-expired key.
   *
   * This method automatically purges expired keys before checking.
   *
   * @return bool
   *   TRUE if a usable key exists, FALSE otherwise.
   */
  public function hasUsableKey(): bool {
    if ($this->hasUsableKeyResult !== NULL) {
      return $this->hasUsableKeyResult;
    }

    // Check provider before state read — skips DB if no provider configured.
    $provider = $this->getSelectedProviderId();
    if ($provider === NULL) {
      return $this->hasUsableKeyResult = FALSE;
    }

    if ($this->purgeExpiredKey()) {
      return $this->hasUsableKeyResult = FALSE;
    }

    $definition = $this->providers[$provider];
    $key = $this->entityTypeManager->getStorage('key')->load($definition['key_id']);
    return $this->hasUsableKeyResult = ($key instanceof KeyInterface && $key->getKeyValue() !== '');
  }

  /**
   * Returns the current key expiry timestamp.
   *
   * This method automatically purges expired keys before checking.
   *
   * @return int|null
   *   The Unix timestamp when the key expires, or NULL if no key is set.
   */
  public function getKeyExpiry(): ?int {
    $this->purgeExpiredKey();
    $expiry = $this->state->get(self::EXPIRY_STATE_KEY);
    return is_int($expiry) ? $expiry : NULL;
  }

  /**
   * Performs a lightweight request-time expiry check.
   *
   * On the common path this avoids loading the key entity by returning early
   * when no provider is configured or the stored expiry is still in the
   * future. Missing or invalid expiry state falls through to the fail-closed
   * purge logic.
   */
  public function purgeExpiredKeyOnRequest(): void {
    if ($this->getSelectedProviderId() === NULL) {
      return;
    }

    $expiry = $this->state->get(self::EXPIRY_STATE_KEY);
    if (is_int($expiry) && $expiry > $this->time->getRequestTime()) {
      return;
    }

    $this->purgeExpiredKey();
  }

  /**
   * Returns the key expiry duration in hours.
   *
   * @return int
   *   The number of hours before keys expire.
   */
  public function getExpiryHours(): int {
    return (int) (self::TTL / 3600);
  }

  /**
   * Purges the temporary key once it has expired.
   *
   * This method is called automatically by hasUsableKey() and getKeyExpiry().
   * It compares the stored expiry timestamp with the current time and clears
   * the key value if the expiry has passed. Missing or invalid expiry state is
   * treated as expired when a managed key value exists.
   *
   * @return bool
   *   TRUE when a key value was purged during this call, FALSE otherwise.
   */
  public function purgeExpiredKey(): bool {
    $provider = $this->getSelectedProviderId();
    if ($provider === NULL) {
      return FALSE;
    }

    $expiry = $this->state->get(self::EXPIRY_STATE_KEY);

    if (!is_int($expiry)) {
      if ($this->hasStoredKeyValue($provider)) {
        $this->clearKeyValue($provider);
        $this->hasUsableKeyResult = NULL;
        return TRUE;
      }
      return FALSE;
    }

    if ($expiry > $this->time->getRequestTime()) {
      return FALSE;
    }

    $this->clearKeyValue($provider);
    $this->state->delete(self::EXPIRY_STATE_KEY);
    $this->hasUsableKeyResult = NULL;
    return TRUE;
  }

  /**
   * Returns the current provider label.
   *
   * @return string|null
   *   The human-readable provider label (e.g., 'OpenAI', 'Anthropic'), or NULL.
   */
  public function getSelectedProviderLabel(): ?string {
    $definition = $this->getSelectedProviderDefinition();
    return $definition['label'] ?? NULL;
  }

  /**
   * Clears any QA-managed provider selection.
   *
   * This method:
   * - Clears all managed key values
   * - Resets the selected provider to empty
   * - Deletes the key expiry timestamp
   * - Resets the static cache.
   */
  public function resetProviderSelection(): void {
    $this->clearManagedKeys();
    $this->configFactory->getEditable(self::SETTINGS)
      ->set('selected_provider', '')
      ->save();
    $this->state->delete(self::EXPIRY_STATE_KEY);

    // Reset static cache.
    $this->selectedProviderIdLoaded = FALSE;
    $this->selectedProviderId = NULL;
  }

  /**
   * Returns the AI settings URL after the key form is submitted.
   *
   * @return \Drupal\Core\Url
   *   The URL object for the AI settings form.
   */
  public function getPostSubmitUrl(): Url {
    return Url::fromRoute('ai.settings_form');
  }

  /**
   * Returns route names that should not trigger the key prompt redirect.
   *
   * @return string[]
   *   Allowed route names.
   */
  public function getAllowedRoutes(): array {
    return [
      'drupalpod_ai_qa.api_key_form',
      'user.logout',
    ];
  }

  /**
   * Ensures the managed key entity exists for a provider.
   *
   * If the key entity already exists, this method upgrades it to use
   * Easy Encryption. Otherwise, it creates a new key entity.
   *
   * @param string $provider
   *   The canonical provider ID.
   *
   * @return \Drupal\key\KeyInterface
   *   The managed key entity.
   */
  private function ensureKeyEntity(string $provider): KeyInterface {
    $definition = $this->providers[$provider];
    $storage = $this->entityTypeManager->getStorage('key');
    $key = $storage->load($definition['key_id']);
    if ($key instanceof KeyInterface) {
      $this->ensureSecureKeyProvider($key);
      return $key;
    }

    $key = $storage->create([
      'id' => $definition['key_id'],
      'label' => $definition['key_label'],
      'description' => 'Temporary QA API key managed by DrupalPod AI QA.',
      'key_type' => 'authentication',
      'key_type_settings' => [],
      'key_provider' => 'easy_encrypted',
      'key_provider_settings' => [],
      'key_input' => 'text_field',
      'key_input_settings' => [],
    ]);
    $key->save();

    return $key;
  }

  /**
   * Clears all managed keys.
   *
   * This method sets all managed key values to empty strings but does not
   * delete the key entities themselves.
   */
  private function clearManagedKeys(): void {
    foreach (array_keys($this->providers) as $provider) {
      $this->clearKeyValue($provider);
    }
  }

  /**
   * Clears a provider's managed key value.
   *
   * @param string $provider
   *   The canonical provider ID.
   */
  private function clearKeyValue(string $provider): void {
    $definition = $this->providers[$provider];
    $storage = $this->entityTypeManager->getStorage('key');

    // Reset cache to ensure we load the current entity from the database.
    $storage->resetCache([$definition['key_id']]);

    $key = $storage->load($definition['key_id']);
    if (!$key instanceof KeyInterface) {
      return;
    }

    if ($key->getKeyProvider() instanceof KeyProviderSettableValueInterface) {
      $key->deleteKeyValue();
    }
    else {
      $key->setKeyValue('');
    }
    $key->save();

    // Reset entity cache again after saving to ensure subsequent entity loads
    // reflect the current stored configuration.
    $storage->resetCache([$definition['key_id']]);

    // Reset provider caches to ensure the change is reflected immediately.
    $this->resetProviderCaches($provider);
  }

  /**
   * Builds a provider definition with the common QA defaults.
   *
   * @param string $machine_name
   *   The provider machine name used by module/config conventions.
   * @param string $label
   *   The provider label.
   * @param array<string, mixed> $overrides
   *   Optional overrides for provider-specific differences.
   *
   * @return array<string, mixed>
   *   The provider definition.
   */
  private function buildProviderDefinition(string $machine_name, string $label, array $overrides = []): array {
    $provider_id = $overrides['provider_id'] ?? $machine_name;

    unset($overrides['provider_id']);

    return $overrides + [
      'label' => $label,
      'module' => 'ai_provider_' . $machine_name,
      'config_name' => 'ai_provider_' . $machine_name . '.settings',
      'config_key' => 'api_key',
      'key_id' => 'drupalpod_ai_qa_' . $provider_id,
      'key_label' => 'DrupalPod QA ' . $label . ' API key',
    ];
  }

  /**
   * Returns whether the managed key currently stores a non-empty value.
   *
   * @param string $provider
   *   The canonical provider ID.
   *
   * @return bool
   *   TRUE when the key entity exists and contains a value.
   */
  private function hasStoredKeyValue(string $provider): bool {
    $definition = $this->providers[$provider];
    $storage = $this->entityTypeManager->getStorage('key');
    $storage->resetCache([$definition['key_id']]);
    $key = $storage->load($definition['key_id']);

    return $key instanceof KeyInterface && $key->getKeyValue() !== '';
  }

  /**
   * Retrieves setup data from the provider, with a local fallback if needed.
   *
   * @param string $provider
   *   The canonical provider plugin ID.
   * @param array<string, mixed> $definition
   *   The provider definition.
   *
   * @return array<string, mixed>
   *   Provider setup data.
   */
  private function getProviderSetupData(string $provider, array $definition): array {
    $setup_data = [];

    try {
      $provider_instance = $this->aiProviderManager->createInstance($provider);
      $setup_data = $provider_instance->getSetupData();
    }
    catch (\Throwable) {
      $setup_data = [];
    }

    $setup_data['key_config_name'] ??= $definition['config_key'];

    return $setup_data;
  }

  /**
   * Clears cached provider data after the API key changes.
   *
   * This method attempts to call the provider's clearModelsCache() method
   * if it exists. If the provider doesn't support this method or cannot
   * be instantiated, it logs a notice that cached data may be stale.
   *
   * For QA environments, stale model caches are not critical. Users can
   * manually clear caches with 'drush cr' if model lists don't update.
   * This avoids the performance impact of clearing the entire cache bin.
   *
   * @param string $provider
   *   The canonical provider plugin ID.
   */
  private function resetProviderCaches(string $provider): void {
    try {
      $provider_instance = $this->aiProviderManager->createInstance($provider);
      if (method_exists($provider_instance, 'clearModelsCache')) {
        $provider_instance->clearModelsCache();
        return;
      }
    }
    catch (\Throwable $e) {
      $this->loggerFactory->get('drupalpod_ai_qa')
        ->warning('Could not instantiate provider @provider to clear caches: @message', [
          '@provider' => $provider,
          '@message' => $e->getMessage(),
        ]);
      return;
    }

    // Provider does not implement clearModelsCache(). Model lists may remain
    // cached until the cache expires or is manually cleared.
    $this->loggerFactory->get('drupalpod_ai_qa')
      ->info('Provider @provider does not support cache clearing. Cached model lists may be stale. Run "drush cr" if needed.', [
        '@provider' => $provider,
      ]);
  }

  /**
   * Upgrades managed keys to Easy Encryption.
   *
   * This method upgrades any pre-existing managed key to the
   * 'easy_encrypted' provider. The key value is preserved during the upgrade.
   *
   * @param \Drupal\key\KeyInterface $key
   *   The key entity to upgrade.
   */
  private function ensureSecureKeyProvider(KeyInterface $key): void {
    if ($key->get('key_provider') === 'easy_encrypted') {
      return;
    }

    $key_value = $key->getKeyValue(TRUE);
    $key->setPlugin('key_provider', 'easy_encrypted');
    $key->set('key_provider_settings', []);

    if ($key_value !== '') {
      $key->setKeyValue($key_value);
    }

    $key->save();
  }

}
