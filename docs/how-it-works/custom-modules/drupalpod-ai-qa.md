# `drupalpod_ai_qa`

This module supports AI provider setup inside Drupal.

It is responsible for:

- Applying the selected AI provider configuration
- Supporting a temporary API key entry flow
- Handling provider-specific setup logic for the environment

In practice, this module creates and manages the DrupalPod AI QA key used by
the configured provider in the environment. It will only be used when the provider
is not set to `amazee`, which has its own provisioning flow.

That key will be prompted for in the Drupal UI, and expires after a limited time.

!!! warning "Public environments in DrupalForge"
    When using DrupalForge, environments being built may be publicly accessible, 
    so any API key being used should be treated as temporary and not tied to a 
    personal account.

    The Drupal admin credentials are set to `admin:admin`, so if someone
    has the environment URL they may also be able to access the site. Treat
    these machines as temporary public environments rather than private
    personal workspaces.

## What It Does

- Uses the provider configuration that was set up earlier in the environment build from `DP_AI_PROVIDER`
- Detects when the DrupalPod AI QA key is missing
- Prompts the user to add a temporary QA API key
- Stores that key using the site key and encryption setup
- Expires that QA key after the configured time window

If no QA API key is present, admins will see a warning in the Drupal UI
to prompt them to add a key:

![Missing QA API key warning](../../resources/how-it-works/missingapikey-warning.png)

The form then submits then stored the key in Drupal's key system, where it is available for the configured provider to use:

![QA AI API key form](../../resources/how-it-works/add-qa-api-key.png)

![Drupal key list showing the DrupalPod AI provider key](../../resources/how-it-works/list-of-keys.png)
