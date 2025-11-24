# DrupalPod AI QA

A flexible QA testing environment for Drupal CMS and AI modules, powered by [DDEV](https://ddev.com).

This project allows you to quickly spin up different configurations of Drupal CMS or Drupal Core to test AI modules and features across different versions.

## Getting started

### Prerequisites

- [DDEV](https://ddev.com/get-started/) installed and running
- Git

### Quick start

1. Clone this repository
2. Navigate to the project directory
3. Run `ddev start`
4. Visit https://drupalpod-ai-qa.ddev.site

That's it! DDEV will automatically run the setup scripts and install Drupal.

### Configuration

Control which Drupal setup and version you want to test using environment variables in `.ddev/config.yaml`:

```yaml
web_environment:
  - DP_STARTER_TEMPLATE=cms  # "cms" or "core"
  - DP_VERSION=1.x           # e.g., "1.x", "2.0.0" for CMS; "11.2.8", "11.x" for core
  - DP_INSTALL_PROFILE=      # Optional: override default profile
  - DP_REBUILD=0             # Set to 1 for clean rebuild
  - DP_AI_VIRTUAL_KEY=       # Optional: AI API key for auto-configuration
```

### Common scenarios

**Test AI modules with Drupal CMS 1.x:**
```yaml
DP_STARTER_TEMPLATE=cms
DP_VERSION=1.x
```

**Test AI modules with Drupal CMS 2.x:**
```yaml
DP_STARTER_TEMPLATE=cms
DP_VERSION=2.0.0
```

**Test with Drupal Core:**
```yaml
DP_STARTER_TEMPLATE=core
DP_VERSION=11.2.8
```

**Clean rebuild:**
```bash
DP_REBUILD=1 ddev start
```

**Auto-configure AI with API key:**
```yaml
DP_AI_VIRTUAL_KEY=sk-your-key-here
```

### Installation details

The setup is automated via DDEV hooks in `.ddev/config.yaml`:
- `init.sh` - Main orchestration script
- `composer_setup.sh` - Generates composer.json and installs dependencies
- `contrib_modules_setup.sh` - Configures devel and admin_toolbar modules
- `fallback_setup.sh` - Sets default configuration values

### Installation options

The Drupal CMS installer offers a list of features preconfigured with smart defaults. You will be able to customize whatever you choose, and add additional features, once you are logged in.

After the installer is complete, you will land on the dashboard.

## Documentation

Coming soon ... [We're working on Drupal CMS specific documentation](https://www.drupal.org/project/drupal_cms/issues/3454527).

In the meantime, learn more about managing a Drupal-based application in the [Drupal User Guide](https://www.drupal.org/docs/user_guide/en/index.html).

## Contributing

Drupal CMS is developed in the open on [Drupal.org](https://www.drupal.org). We are grateful to the community for reporting bugs and contributing fixes and improvements.

[Report issues in the queue](https://drupal.org/node/add/project-issue/drupal_cms), providing as much detail as you can. You can also join the #drupal-cms-support channel in the [Drupal Slack community](https://www.drupal.org/slack).

Drupal CMS has adopted a [code of conduct](https://www.drupal.org/dcoc) that we expect all participants to adhere to.

To contribute to Drupal CMS development, see the [drupal_cms project](https://www.drupal.org/project/drupal_cms).

## License

Drupal CMS and all derivative works are licensed under the [GNU General Public License, version 2 or later](http://www.gnu.org/licenses/old-licenses/gpl-2.0.html).

Learn about the [Drupal trademark and logo policy here](https://www.drupal.com/trademark).
