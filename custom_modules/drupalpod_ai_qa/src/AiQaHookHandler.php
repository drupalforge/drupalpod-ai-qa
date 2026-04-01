<?php

declare(strict_types=1);

namespace Drupal\drupalpod_ai_qa;

use Drupal\Core\Form\FormStateInterface;
use Drupal\Core\Messenger\MessengerInterface;
use Drupal\Core\Routing\AdminContext;
use Drupal\Core\Routing\CurrentRouteMatch;
use Drupal\Core\StringTranslation\StringTranslationTrait;
use Drupal\Core\StringTranslation\TranslationInterface;
use Drupal\Core\Session\AccountProxyInterface;
use Drupal\Core\Url;
use Drupal\key\Entity\Key;
use Drupal\user\UserInterface;
use Symfony\Component\HttpFoundation\RequestStack;

/**
 * Handles hook-driven UI behavior for DrupalPod AI QA.
 */
final class AiQaHookHandler {

  use StringTranslationTrait;

  /**
   * Routes that should never show the missing-key warning.
   *
   * @var string[]
   */
  private const ALLOWED_ROUTES = [
    'drupalpod_ai_qa.api_key_form',
    'user.logout',
  ];

  /**
   * Constructs the hook handler.
   *
   * @param \Drupal\drupalpod_ai_qa\AiQaProviderManager $providerManager
   *   The provider manager.
   * @param \Drupal\Core\Messenger\MessengerInterface $messenger
   *   The messenger service.
   * @param \Drupal\Core\Routing\CurrentRouteMatch $routeMatch
   *   The current route match service.
   * @param \Drupal\Core\Routing\AdminContext $adminContext
   *   The admin route context service.
   * @param \Symfony\Component\HttpFoundation\RequestStack $requestStack
   *   The request stack.
   * @param \Drupal\Core\Session\AccountProxyInterface $currentUser
   *   The current user.
   * @param \Drupal\Core\StringTranslation\TranslationInterface $stringTranslation
   *   The string translation service.
   */
  public function __construct(
    private readonly AiQaProviderManager $providerManager,
    private readonly MessengerInterface $messenger,
    private readonly CurrentRouteMatch $routeMatch,
    private readonly AdminContext $adminContext,
    private readonly RequestStack $requestStack,
    private readonly AccountProxyInterface $currentUser,
    TranslationInterface $stringTranslation,
  ) {
    $this->stringTranslation = $stringTranslation;
  }

  /**
   * Runs cron-time expiry cleanup.
   */
  public function handleCron(): void {
    $this->providerManager->purgeExpiredKey();
  }

  /**
   * Adds the key warning for admin users after login when needed.
   *
   * @param \Drupal\user\UserInterface $account
   *   The logged-in user account.
   */
  public function handleUserLogin(UserInterface $account): void {
    if (!$account->hasPermission('administer ai providers')) {
      return;
    }

    if (!$this->shouldPromptForKey()) {
      return;
    }

    $this->addMissingKeyWarning();
  }

  /**
   * Alters the login form submit handlers.
   *
   * @param array<string, mixed> $form
   *   The form array.
   */
  public function alterUserLoginForm(array &$form): void {
    $form['#submit'][] = 'drupalpod_ai_qa_user_login_form_submit';
  }

  /**
   * Redirects to the managed key form after login when needed.
   *
   * @param \Drupal\Core\Form\FormStateInterface $form_state
   *   The form state.
   */
  public function handleUserLoginFormSubmit(FormStateInterface $form_state): void {
    if (!$this->shouldPromptForKey()) {
      return;
    }

    $request = $this->requestStack->getCurrentRequest();
    if ($request !== NULL) {
      $request->query->remove('destination');
    }

    $form_state->setRedirectUrl($this->getKeyEditUrl());
  }

  /**
   * Adds the missing-key warning on admin pages when appropriate.
   */
  public function handlePageTop(): void {
    if (!$this->currentUser->isAuthenticated() || !$this->currentUser->hasPermission('administer ai providers')) {
      return;
    }

    $route_name = $this->routeMatch->getRouteName();
    if ($route_name === NULL) {
      return;
    }

    if (in_array($route_name, self::ALLOWED_ROUTES, TRUE)) {
      return;
    }

    if ($route_name === 'entity.key.edit_form') {
      $key = $this->routeMatch->getParameter('key');
      if ($key instanceof Key && $key->id() === AiQaProviderManager::KEY_ID) {
        return;
      }
    }

    $route_object = $this->routeMatch->getRouteObject();
    if ($route_object === NULL || !$this->adminContext->isAdminRoute($route_object)) {
      return;
    }

    if (!$this->shouldPromptForKey()) {
      return;
    }

    $this->addMissingKeyWarning();
  }

  /**
   * Builds the managed key edit URL.
   *
   * @return \Drupal\Core\Url
   *   The key edit URL.
   */
  public function getKeyEditUrl(): Url {
    return Url::fromRoute('drupalpod_ai_qa.api_key_form');
  }

  /**
   * Returns whether the current request should prompt for a QA key.
   *
   * @return bool
   *   TRUE if a provider is configured but no usable key exists.
   */
  private function shouldPromptForKey(): bool {
    return $this->providerManager->getSelectedProviderId() !== NULL
      && !$this->providerManager->hasUsableKey();
  }

  /**
   * Adds the standard missing-key warning message.
   */
  private function addMissingKeyWarning(): void {
    $this->messenger->addWarning($this->t(
      'No QA AI API key is set. <a href=":url">Add your API key</a> to use AI features.',
      [':url' => $this->getKeyEditUrl()->toString()],
    ));
  }

}
