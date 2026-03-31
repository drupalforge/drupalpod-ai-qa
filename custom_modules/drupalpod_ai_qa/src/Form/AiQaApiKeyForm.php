<?php

declare(strict_types=1);

namespace Drupal\drupalpod_ai_qa\Form;

use Drupal\Core\Datetime\DateFormatterInterface;
use Drupal\Core\Form\FormBase;
use Drupal\Core\Form\FormStateInterface;
use Drupal\drupalpod_ai_qa\AiQaProviderManager;
use Symfony\Component\DependencyInjection\ContainerInterface;

/**
 * Collects a temporary QA API key for the configured provider.
 */
final class AiQaApiKeyForm extends FormBase {

  /**
   * Constructs the QA API key form.
   *
   * @param \Drupal\drupalpod_ai_qa\AiQaProviderManager $providerManager
   *   The QA provider manager.
   * @param \Drupal\Core\Datetime\DateFormatterInterface $dateFormatter
   *   The date formatter service.
   */
  public function __construct(
    private readonly AiQaProviderManager $providerManager,
    private readonly DateFormatterInterface $dateFormatter,
  ) {
  }

  /**
   * {@inheritdoc}
   */
  public static function create(ContainerInterface $container): static {
    return new static(
      $container->get('drupalpod_ai_qa.provider_manager'),
      $container->get('date.formatter'),
    );
  }

  /**
   * {@inheritdoc}
   */
  public function getFormId(): string {
    return 'drupalpod_ai_qa_api_key_form';
  }

  /**
   * {@inheritdoc}
   *
   * Note: CSRF protection is automatically handled by Form API.
   */
  public function buildForm(array $form, FormStateInterface $form_state): array {
    $provider_label = $this->providerManager->getSelectedProviderLabel();
    $expiry = $this->providerManager->getKeyExpiry();

    if ($provider_label === NULL) {
      $form['message'] = [
        '#type' => 'item',
        '#markup' => $this->t('No QA AI provider is configured for this environment.'),
      ];
      return $form;
    }

    $form['intro'] = [
      '#type' => 'item',
      '#title' => $this->t('@provider key required', ['@provider' => $provider_label]),
      '#markup' => '<p>' . $this->t('This QA environment is configured for @provider. Enter an API key to continue.', [
        '@provider' => $provider_label,
      ]) . '</p>',
    ];

    $form['warning'] = [
      '#type' => 'container',
      'message' => [
        '#markup' => '<p><strong>' . $this->t('Warning:') . '</strong> ' . $this->t('This is a QA environment. Your API key is stored temporarily in site configuration, may be discoverable by privileged users, and will be cleared after @hours hours.', ['@hours' => $this->providerManager->getExpiryHours()]) . '</p>',
      ],
    ];

    if ($expiry !== NULL) {
      $form['status'] = [
        '#type' => 'item',
        '#markup' => '<p>' . $this->t('The current temporary key expires at @time.', [
          '@time' => $this->dateFormatter->format($expiry, 'short'),
        ]) . '</p>',
      ];
    }

    $form['api_key'] = [
      '#type' => 'password',
      '#title' => $this->t('@provider API key', ['@provider' => $provider_label]),
      '#required' => TRUE,
      '#maxlength' => 512,
      '#description' => $this->t('Paste a temporary API key for this QA session.'),
    ];

    $form['actions'] = ['#type' => 'actions'];
    $form['actions']['submit'] = [
      '#type' => 'submit',
      '#value' => $this->t('Save temporary API key'),
      '#button_type' => 'primary',
    ];

    return $form;
  }

  /**
   * {@inheritdoc}
   */
  public function validateForm(array &$form, FormStateInterface $form_state): void {
    $api_key = trim((string) $form_state->getValue('api_key'));

    if ($api_key === '') {
      $form_state->setErrorByName('api_key', $this->t('Enter an API key.'));
      return;
    }

    // Validate format: allow alphanumeric, common separators, and base64 chars.
    // Base64-encoded keys may contain +, /, and = (padding).
    if (!preg_match('/^[a-zA-Z0-9_\-+\/=.]+$/', $api_key)) {
      $form_state->setErrorByName('api_key', $this->t('API key contains invalid characters. Only letters, numbers, and common API key characters are allowed.'));
      return;
    }

    // Check minimum length (most API keys are at least 20 chars).
    if (strlen($api_key) < 20) {
      $form_state->setErrorByName('api_key', $this->t('API key appears too short. Most API keys are at least 20 characters.'));
      return;
    }

    $validation_error = $this->providerManager->validateTemporaryKey($api_key);
    if ($validation_error !== NULL) {
      $form_state->setErrorByName('api_key', $validation_error);
    }
  }

  /**
   * {@inheritdoc}
   */
  public function submitForm(array &$form, FormStateInterface $form_state): void {
    $this->providerManager->storeTemporaryKey(trim((string) $form_state->getValue('api_key')));
    $this->messenger()->addStatus($this->t('Temporary API key saved. It will expire in @hours hours.', ['@hours' => $this->providerManager->getExpiryHours()]));
    $redirect_url = $this->providerManager->getPostSubmitUrl();
    if ($redirect_url !== NULL) {
      $form_state->setRedirectUrl($redirect_url);
    }
  }

}
