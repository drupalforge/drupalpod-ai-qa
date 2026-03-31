<?php

declare(strict_types=1);

namespace Drupal\Tests\drupalpod_ai_qa\Kernel;

use Drupal\KernelTests\KernelTestBase;
use Drupal\drupalpod_ai_qa\AiQaProviderManager;
use Drupal\easy_encryption\KeyManagement\KeyActivatorInterface;
use Drupal\easy_encryption\KeyManagement\KeyGeneratorInterface;
use PHPUnit\Framework\Attributes\RunTestsInSeparateProcesses;

/**
 * Tests QA AI provider setup and expiry handling.
 *
 * @group drupalpod_ai_qa
 */
#[RunTestsInSeparateProcesses]
final class AiQaProviderManagerKernelTest extends KernelTestBase {

  /**
   * {@inheritdoc}
   */
  protected static $modules = [
    'system',
    'user',
    'key',
    'easy_encryption',
    'ai',
    'ai_provider_openai',
    'drupalpod_ai_qa',
  ];

  /**
   * The provider manager service.
   */
  private AiQaProviderManager $providerManager;

  /**
   * {@inheritdoc}
   */
  protected function setUp(): void {
    parent::setUp();

    $this->installEntitySchema('user');
    $this->installConfig(['system', 'user', 'key', 'easy_encryption', 'ai', 'ai_provider_openai', 'drupalpod_ai_qa']);
    $this->initializeEasyEncryption();

    $this->providerManager = $this->container->get('drupalpod_ai_qa.provider_manager');
  }

  /**
   * Tests that applying a provider creates the key entity and sets defaults.
   */
  public function testApplyProviderCreatesManagedKeyAndDefaults(): void {
    $this->providerManager->applyProvider('openai');

    $settings = $this->config('drupalpod_ai_qa.settings');
    self::assertSame('openai', $settings->get('selected_provider'));

    $provider_config = $this->config('ai_provider_openai.settings');
    self::assertSame('drupalpod_ai_qa_openai', $provider_config->get('api_key'));

    $key = $this->container->get('entity_type.manager')->getStorage('key')->load('drupalpod_ai_qa_openai');
    self::assertNotNull($key);

    $defaults = $this->config('ai.settings')->get('default_providers');
    self::assertSame('openai', $defaults['chat']['provider_id']);
    self::assertSame('gpt-5.2', $defaults['chat']['model_id']);
    self::assertSame('text-embedding-3-small', $defaults['embeddings']['model_id']);
  }

  /**
   * Tests that a temporary managed key expires and is purged correctly.
   */
  public function testTemporaryKeyExpiresAfterPurge(): void {
    $this->providerManager->applyProvider('openai');
    $this->providerManager->storeTemporaryKey('secret-value');

    self::assertTrue($this->providerManager->hasUsableKey());
    self::assertNotNull($this->providerManager->getKeyExpiry());

    // Set expiry time to the past to simulate an expired key.
    $this->container->get('state')->set('drupalpod_ai_qa.key_expires_at', $this->container->get('datetime.time')->getRequestTime() - 1);
    $this->resetKeyValueStaticCache();

    // Clear entity cache before purging to ensure a fresh load.
    $key_storage = $this->container->get('entity_type.manager')->getStorage('key');
    $key_storage->resetCache(['drupalpod_ai_qa_openai']);

    $this->providerManager->purgeExpiredKey();

    // Clear entity cache again after purging to force reload from database.
    $key_storage->resetCache(['drupalpod_ai_qa_openai']);

    // Verify the key was cleared by loading it directly.
    $key = $key_storage->load('drupalpod_ai_qa_openai');
    self::assertSame('', $key->getKeyValue(TRUE));

    // hasUsableKey() should also return false now.
    $this->resetKeyValueStaticCache();
    self::assertFalse($this->providerManager->hasUsableKey());
  }

  /**
   * Tests that missing expiry state fails closed and clears the key.
   */
  public function testMissingExpiryStateClearsStoredKey(): void {
    $this->providerManager->applyProvider('openai');
    $this->providerManager->storeTemporaryKey('secret-value');

    $this->container->get('state')->delete('drupalpod_ai_qa.key_expires_at');
    $this->resetKeyValueStaticCache();

    $key_storage = $this->container->get('entity_type.manager')->getStorage('key');
    $key_storage->resetCache(['drupalpod_ai_qa_openai']);

    self::assertFalse($this->providerManager->hasUsableKey());
    self::assertNull($this->providerManager->getKeyExpiry());

    $key_storage->resetCache(['drupalpod_ai_qa_openai']);
    $key = $key_storage->load('drupalpod_ai_qa_openai');
    self::assertSame('', $key->getKeyValue(TRUE));
  }

  /**
   * Ensures Easy Encryption has an active encryption key for tests.
   */
  private function initializeEasyEncryption(): void {
    $generator = $this->container->get(KeyGeneratorInterface::class);
    $activator = $this->container->get(KeyActivatorInterface::class);
    $key_id = $generator->generate();
    $activator->activate($key_id);
  }

  /**
   * Resets the Key entity static cache for getKeyValue() during this request.
   */
  private function resetKeyValueStaticCache(): void {
    drupal_static_reset('getKeyValue');
  }

}
