---
hide:
  - navigation
---

# DrupalPod AI QA Documentation

DrupalPod AI QA is an automation tool for launching Drupal CMS or Drupal core
environments preconfigured for testing AI module patches, issue forks, and pull
requests.

The [DrupalPod AI QA helper extension](https://chromewebstore.google.com/detail/drupalpod-ai-qa-helper-ex/nfemkgbmpcfibkpjifoaimldfjejinji)
reads issue details from Drupal.org and can launch the environment to be tested
in [DrupalForge](https://www.drupalforge.org/). You can also run this project locally with DDEV when you 
need direct control over the codebase.

This documentation is organised into sections covering how the tool works, how
to use it, and how to work in the codebase.

!!! info "Looking to get started?"
    If you just want to launch and use DrupalPod AI QA, start with the
    [Step-by-Step Guide](how-to-use/step-by-step-guide.md).

## What It Does

The extension prepares the environment configuration from the issue context:

![DrupalPod AI QA extension configuration view](resources/homepage/extension-configuration.png)

The resulting environment is then launched in DrupalForge and exposed through
DevPanel:

![DrupalForge DevPanel overview after deployment](resources/homepage/devpanel-overview.png)

## How It Works

- [How It Works](how-it-works/index.md)
  gives an overview of the build process.
- [Build Flow](how-it-works/build-flow.md)
  explains the order of the main scripts and the generated manifest.
- [Custom Modules](how-it-works/custom-modules/index.md)
  explains the Drupal modules included in this repository.
- [Resolution Modes](how-it-works/resolution-modes.md)
  explains version resolution, compatibility checks, and lenient dependency handling.

## How to Use

- [Common Use Cases](how-to-use/common-use-cases.md)
  explains the main issue setups supported by the tool.
- [Choosing an AI Provider](how-to-use/provider-selection.md)
  explains how provider selection affects the environment and key flow.
- [Step-by-Step Guide](how-to-use/step-by-step-guide.md)
  covers the hosted workflow using the Chrome extension and DrupalForge.
- [VS Code in Browser](how-to-use/vscode-in-browser.md)
  covers the hosted browser-based editing and terminal workflow.
- [Local DDEV Guide](how-to-use/local-ddev-guide.md)
  covers local setup and override patterns.
- [Configuration Reference](how-to-use/configuration-reference.md)
  lists the main environment variables and build inputs.
- [Troubleshooting](how-to-use/troubleshooting.md)
  covers common environment, build, and compatibility issues.

## Developer Documentation

- [Developer Guide](developer-guide.md)
  covers local repo, branch, and fork workflows.
- [Development](development.md)
  covers the script architecture and implementation notes.
- [Testing](testing.md)
  covers the BATS suite and scenario runner workflow.

## Key Links

- [DrupalPod AI QA helper extension](https://chromewebstore.google.com/detail/drupalpod-ai-qa-helper-ex/nfemkgbmpcfibkpjifoaimldfjejinji)
- [DrupalForge](https://www.drupalforge.org/)
- [AI project on Drupal.org](https://www.drupal.org/project/ai)
- [DrupalPod AI QA Git repository](https://git.drupalcode.org/project/drupalpod_ai_qa)
