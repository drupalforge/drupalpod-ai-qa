<?php

declare(strict_types=1);

namespace Drupal\drupalpod_ai_qa\Commands;

use Drupal\drupalpod_ai_qa\AiQaProviderManager;
use Drush\Commands\DrushCommands;

/**
 * Drush commands for DrupalPod AI QA.
 */
final class AiQaCommands extends DrushCommands {

  /**
   * Constructs the Drush command handler.
   *
   * @param \Drupal\drupalpod_ai_qa\AiQaProviderManager $providerManager
   *   The provider manager.
   */
  public function __construct(
    private readonly AiQaProviderManager $providerManager,
  ) {
    parent::__construct();
  }

  /**
   * Applies DrupalPod AI QA provider configuration.
   *
   * @param string $provider
   *   The provider ID or alias, for example openai, anthropic, or amazeeai.
   *
   * @command drupalpod-ai-qa:apply-provider
   * @aliases dpaiqa-apply-provider
   */
  public function applyProvider(string $provider): void {
    if (!$this->providerManager->applyProvider($provider)) {
      throw new \RuntimeException(sprintf('Failed to apply provider "%s".', $provider));
    }

    $this->io()->success(sprintf('Applied DrupalPod AI QA provider: %s', $this->providerManager->normalizeProvider($provider)));
  }

}
