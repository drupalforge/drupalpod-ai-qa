<?php

declare(strict_types=1);

namespace Drupal\drupalpod_ai_qa\EventSubscriber;

use Drupal\drupalpod_ai_qa\AiQaProviderManager;
use Drupal\Core\Url;
use Drupal\key\Entity\Key;
use Symfony\Component\EventDispatcher\EventSubscriberInterface;
use Symfony\Component\HttpFoundation\RedirectResponse;
use Symfony\Component\HttpKernel\Event\RequestEvent;
use Symfony\Component\HttpKernel\KernelEvents;

/**
 * Enforces QA key expiry during normal HTTP requests.
 */
final class KeyExpirySubscriber implements EventSubscriberInterface {

  /**
   * Constructs a key expiry subscriber.
   *
   * @param \Drupal\drupalpod_ai_qa\AiQaProviderManager $providerManager
   *   The provider manager.
   */
  public function __construct(
    private readonly AiQaProviderManager $providerManager,
  ) {
  }

  /**
   * Purges expired QA keys on the main HTTP request.
   *
   * @param \Symfony\Component\HttpKernel\Event\RequestEvent $event
   *   The request event.
   */
  public function onRequest(RequestEvent $event): void {
    if (!$event->isMainRequest()) {
      return;
    }

    $this->providerManager->purgeExpiredKeyOnRequest();

    $request = $event->getRequest();
    if ($request->attributes->get('_route') !== 'entity.key.edit_form') {
      return;
    }

    $key = $request->attributes->get('key');
    if (
      $key !== AiQaProviderManager::KEY_ID &&
      (!$key instanceof Key || $key->id() !== AiQaProviderManager::KEY_ID)
    ) {
      return;
    }

    $event->setResponse(new RedirectResponse(
      Url::fromRoute('drupalpod_ai_qa.api_key_form')->toString(),
    ));
  }

  /**
   * {@inheritdoc}
   */
  public static function getSubscribedEvents(): array {
    return [
      KernelEvents::REQUEST => ['onRequest', 100],
    ];
  }

}
