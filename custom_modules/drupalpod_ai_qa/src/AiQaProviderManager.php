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
use Drupal\key\KeyInterface;
use Drupal\key\Plugin\KeyProviderSettableValueInterface;

/**
 * Manages QA AI provider setup and QA AI API key storage.
 */
final class AiQaProviderManager {

  /**
   * The single managed key entity ID, shared across all providers.
   */
  public const KEY_ID = 'drupalpod_ai_qa';

  /**
   * The managed key entity label.
   */
  private const KEY_LABEL = 'DrupalPod AI Provider Key';

  /**
   * The expiry state key.
   */
  private const EXPIRY_STATE_KEY = 'drupalpod_ai_qa.key_expires_at';

  /**
   * Time-to-live for QA keys in seconds.
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

  /**
   * Constructs the QA provider manager.
   *
   * @param \Drupal\Core\Config\ConfigFactoryInterface $configFactory
   *   The config factory.
   * @param \Drupal\Core\Entity\EntityTypeManagerInterface $entityTypeManager
   *   The entity type manager.
   * @param \Drupal\Core\State\StateInterface $state
   *   The state service.
   * @param \Drupal\Component\Datetime\TimeInterface $time
   *   The time service.
   * @param \Drupal\Core\Extension\ModuleHandlerInterface $moduleHandler
   *   The module handler.
   * @param \Drupal\ai\AiProviderPluginManager $aiProviderManager
   *   The AI provider plugin manager.
   * @param \Drupal\Core\Logger\LoggerChannelFactoryInterface $loggerFactory
   *   The logger factory.
   */
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
      'amazeeai' => $this->buildProviderDefinition('amazeeio', 'amazee.ai'),
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
   * Returns the canonical selected provider ID.
   *
   * @return string|null
   *   The canonical provider ID, or NULL if no provider uses the QA key.
   */
  public function getSelectedProviderId(): ?string {
    if (!$this->selectedProviderIdLoaded) {
      $this->selectedProviderId = $this->getManagedKeyProviderFromDefaults()
        ?? $this->getManagedKeyProviderFromProviderConfig();
      $this->selectedProviderIdLoaded = TRUE;
    }
    return $this->selectedProviderId;
  }

  /**
   * Returns the selected provider label.
   *
   * @return string|null
   *   The selected provider label, or NULL if none is configured.
   */
  public function getSelectedProviderLabel(): ?string {
    $provider = $this->getSelectedProviderId();
    if ($provider === NULL) {
      return NULL;
    }

    return $this->providers[$provider]['label'] ?? NULL;
  }

  /**
   * Applies QA defaults for the selected provider.
   *
   * This method:
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
    $original = $provider;
    $provider = $this->normalizeProvider($provider);
    if ($provider === NULL) {
      $this->loggerFactory->get('drupalpod_ai_qa')->error('Invalid provider: @provider', ['@provider' => $original]);
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

    $this->clearKeyValue();

    $setup_data = $this->getProviderSetupData($definition);

    // If the provider already has its own key configured (not our managed key),
    // leave its config untouched — we don't want to overwrite a permanent key
    // or subject it to the QA TTL expiry.
    $hasOwnKey = $this->providerUsesOwnKey($definition);

    if (!$hasOwnKey) {
      $this->ensureKeyEntity();

      $provider_config = $this->configFactory->getEditable($definition['config_name']);
      $provider_config->set($setup_data['key_config_name'] ?? $definition['config_key'], self::KEY_ID);
      foreach (($definition['extra_config'] ?? []) as $key => $value) {
        $provider_config->set($key, $value);
      }
      $provider_config->save();
    }

    $defaults = [];
    foreach (($setup_data['default_models'] ?? []) as $operation => $model_id) {
      $defaults[$operation] = [
        'provider_id' => $definition['plugin_id'],
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
   * Records the expiry timestamp for a key that was just saved.
   *
   * Called from hook_key_insert() / hook_key_update() so that the managed QA
   * key expires after the TTL. If the key ID matches the managed QA key,
   * provider caches are also reset.
   *
   * @param string $key_id
   *   The key entity ID that was saved.
   */
  public function recordKeyExpiry(string $key_id): void {
    $this->state->set(self::EXPIRY_STATE_KEY, $this->time->getRequestTime() + self::TTL);
    $this->hasUsableKeyResult = NULL;

    if ($key_id === self::KEY_ID) {
      $provider = $this->getSelectedProviderId();
      if ($provider !== NULL) {
        $this->resetProviderCaches($provider);
      }
    }
  }

  /**
   * Returns TRUE when the managed QA key has a non-expired value.
   *
   * @return bool
   *   TRUE if a usable key exists, FALSE otherwise.
   */
  public function hasUsableKey(): bool {
    if ($this->hasUsableKeyResult !== NULL) {
      return $this->hasUsableKeyResult;
    }

    if ($this->purgeExpiredKey()) {
      return $this->hasUsableKeyResult = FALSE;
    }

    $key = $this->entityTypeManager->getStorage('key')->load(self::KEY_ID);
    return $this->hasUsableKeyResult = ($key instanceof KeyInterface && $key->getKeyValue() !== '');
  }

  /**
   * Performs a lightweight request-time expiry check.
   *
   * On the common path this avoids loading the key entity when the stored
   * expiry is still in the future. Missing or invalid expiry state falls
   * through to the fail-closed purge logic.
   */
  public function purgeExpiredKeyOnRequest(): void {
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
   * Returns the stored expiry timestamp for the managed QA key.
   *
   * @return int|null
   *   The expiry timestamp, or NULL if none is recorded.
   */
  public function getKeyExpiry(): ?int {
    $expiry = $this->state->get(self::EXPIRY_STATE_KEY);
    return is_int($expiry) ? $expiry : NULL;
  }

  /**
   * Validates that the selected provider can load its configured models.
   *
   * If the provider is also the default for one or more operations, this
   * additionally verifies that the configured default model IDs still exist.
   *
   * @param string|null $api_key
   *   An optional API key to authenticate the provider instance with before
   *   validating. When NULL, the currently configured key is used.
   *
   * @return string|null
   *   A user-facing validation error message, or NULL if validation passed.
   */
  public function validateSelectedProviderModels(?string $api_key = NULL): ?string {
    $provider = $this->getSelectedProviderId();
    if ($provider === NULL) {
      return (string) t(
        'No AI provider is currently configured to use the QA AI API key.',
      );
    }

    $definition = $this->providers[$provider];

    try {
      $provider_instance = $this->aiProviderManager->createInstance($definition['plugin_id']);
      if ($api_key !== NULL && $api_key !== '') {
        $provider_instance->setAuthentication($api_key);
      }
      $provider_instance->getConfiguredModels();

      $defaults = $this->configFactory->get('ai.settings')->get('default_providers') ?? [];
      foreach ($defaults as $operation_type => $default_provider) {
        if (($default_provider['provider_id'] ?? NULL) !== $definition['plugin_id']) {
          continue;
        }

        $model_id = $default_provider['model_id'] ?? NULL;
        if (!is_string($model_id) || $model_id === '') {
          continue;
        }

        $models = $provider_instance->getConfiguredModels((string) $operation_type);
        if (!array_key_exists($model_id, $models)) {
          return (string) t('The default model "@model" could not be found for the @provider provider.', [
            '@model' => $model_id,
            '@provider' => $definition['label'],
          ]);
        }
      }

      return NULL;
    }
    catch (\Throwable $e) {
      $this->loggerFactory->get('drupalpod_ai_qa')->warning('Provider model validation failed for @provider: @message', [
        '@provider' => $provider,
        '@message' => $e->getMessage(),
      ]);

      return (string) t('@provider model validation failed. Please verify the API key and available credits.', [
        '@provider' => $definition['label'],
      ]);
    }
  }

  /**
   * Validates a submitted QA AI API key for the selected provider.
   *
   * @param string $api_key
   *   The submitted API key.
   *
   * @return string|null
   *   A validation error, or NULL if the key is valid.
   */
  public function validateTemporaryKey(string $api_key): ?string {
    return $this->validateSelectedProviderModels($api_key);
  }

  /**
   * Stores the managed QA AI API key and records its expiry.
   *
   * @param string $api_key
   *   The API key to store.
   */
  public function storeTemporaryKey(string $api_key): void {
    $key = $this->ensureKeyEntity();
    $key->setKeyValue($api_key);
    $key->save();
    $this->recordKeyExpiry(self::KEY_ID);
  }

  /**
   * Purges the QA AI API key once it has expired.
   *
   * This method is called automatically by hasUsableKey(). It compares the
   * stored expiry timestamp with the current time and clears the key value if
   * the expiry has passed. Missing or invalid expiry state is treated as
   * expired when a managed key value exists.
   *
   * @return bool
   *   TRUE when a key value was purged during this call, FALSE otherwise.
   */
  public function purgeExpiredKey(): bool {
    $expiry = $this->state->get(self::EXPIRY_STATE_KEY);

    if (!is_int($expiry)) {
      if ($this->hasStoredKeyValue()) {
        $this->clearKeyValue();
        $this->hasUsableKeyResult = NULL;
        return TRUE;
      }
      return FALSE;
    }

    if ($expiry > $this->time->getRequestTime()) {
      return FALSE;
    }

    $this->clearKeyValue();
    $this->state->delete(self::EXPIRY_STATE_KEY);
    $this->hasUsableKeyResult = NULL;
    return TRUE;
  }

  /**
   * Ensures the managed key entity exists.
   *
   * If the key entity already exists, this method upgrades it to use
   * Easy Encryption. Otherwise, it creates a new key entity.
   *
   * @return \Drupal\key\KeyInterface
   *   The managed key entity.
   */
  private function ensureKeyEntity(): KeyInterface {
    $storage = $this->entityTypeManager->getStorage('key');
    $key = $storage->load(self::KEY_ID);
    if ($key instanceof KeyInterface) {
      $this->ensureSecureKeyProvider($key);
      return $key;
    }

    $key = $storage->create([
      'id' => self::KEY_ID,
      'label' => self::KEY_LABEL,
      'description' => 'QA AI API key managed by DrupalPod AI QA.',
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
   * Clears the managed key value without deleting the entity.
   */
  private function clearKeyValue(): void {
    $storage = $this->entityTypeManager->getStorage('key');
    $storage->resetCache([self::KEY_ID]);

    $key = $storage->load(self::KEY_ID);
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

    $storage->resetCache([self::KEY_ID]);

    $provider = $this->getSelectedProviderId();
    if ($provider !== NULL) {
      $this->resetProviderCaches($provider);
    }
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
    return $overrides + [
      'label' => $label,
      'plugin_id' => $machine_name,
      'module' => 'ai_provider_' . $machine_name,
      'config_name' => 'ai_provider_' . $machine_name . '.settings',
      'config_key' => 'api_key',
    ];
  }

  /**
   * Returns whether the managed key currently stores a non-empty value.
   *
   * @return bool
   *   TRUE when the key entity exists and contains a value.
   */
  private function hasStoredKeyValue(): bool {
    $storage = $this->entityTypeManager->getStorage('key');
    $storage->resetCache([self::KEY_ID]);
    $key = $storage->load(self::KEY_ID);

    return $key instanceof KeyInterface && $key->getKeyValue() !== '';
  }

  /**
   * Retrieves setup data from the provider, with a local fallback if needed.
   *
   * @param array<string, mixed> $definition
   *   The provider definition.
   *
   * @return array<string, mixed>
   *   Provider setup data.
   */
  private function getProviderSetupData(array $definition): array {
    $setup_data = [];

    try {
      $provider_instance = $this->aiProviderManager->createInstance($definition['plugin_id']);
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
      $provider_instance = $this->aiProviderManager->createInstance($this->providers[$provider]['plugin_id']);
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
   * Returns whether a provider is using its own key instead of the QA key.
   *
   * @param array<string, mixed> $definition
   *   The provider definition.
   *
   * @return bool
   *   TRUE if the provider config points at another key.
   */
  private function providerUsesOwnKey(array $definition): bool {
    $config_key = $definition['config_key'] ?? 'api_key';
    $value = $this->configFactory->get($definition['config_name'])->get($config_key);

    return is_string($value) && $value !== '' && $value !== self::KEY_ID;
  }

  /**
   * Returns the managed-key provider referenced by AI defaults, if any.
   *
   * @return string|null
   *   The canonical provider ID, or NULL if none matches.
   */
  private function getManagedKeyProviderFromDefaults(): ?string {
    $defaults = $this->configFactory->get('ai.settings')->get('default_providers');
    if (!is_array($defaults)) {
      return NULL;
    }

    foreach ($defaults as $default_provider) {
      if (!is_array($default_provider)) {
        continue;
      }

      $provider = $this->normalizeProvider($default_provider['provider_id'] ?? NULL);
      if ($provider === NULL) {
        continue;
      }

      $definition = $this->providers[$provider] ?? NULL;
      if (!is_array($definition)) {
        continue;
      }

      $config_key = $definition['config_key'] ?? 'api_key';
      $value = $this->configFactory
        ->get($definition['config_name'])
        ->get($config_key);

      if ($value === self::KEY_ID) {
        return $provider;
      }
    }

    return NULL;
  }

  /**
   * Returns the first provider config that points at the managed QA key.
   *
   * @return string|null
   *   The canonical provider ID, or NULL if none matches.
   */
  private function getManagedKeyProviderFromProviderConfig(): ?string {
    foreach ($this->providers as $provider => $definition) {
      $config_key = $definition['config_key'] ?? 'api_key';
      $value = $this->configFactory
        ->get($definition['config_name'])
        ->get($config_key);

      if ($value === self::KEY_ID) {
        return $provider;
      }
    }

    return NULL;
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
