# How It Works

DrupalPod AI QA builds a Drupal environment around the issue you want to work
with.

At a high level, it does three things:

- Decides which Drupal and AI versions should be used
- Resolves which modules are compatible with that setup
- Builds a ready-to-use environment locally or in DrupalForge

This page explains the main flow for people who want a clearer idea of what the
tool is doing behind the scenes without reading the shell scripts directly.

## In This Section

- [Build Flow](build-flow.md) explains the order of the build and what the main scripts do
- [Custom Modules](custom-modules/index.md) explains the custom modules included in this repository
- [Resolution Modes](resolution-modes.md) explains auto-detect, pinned resolution, compatibility skipping, and lenient dependency handling

## Where to Read More

- [Common Use Cases](../how-to-use/common-use-cases.md) for the main issue setups
- [Step-by-Step Guide](../how-to-use/step-by-step-guide.md) for the guided workflow
- [Configuration Reference](../how-to-use/configuration-reference.md) for the input variables
- [Development](../development.md) for script-level implementation details
