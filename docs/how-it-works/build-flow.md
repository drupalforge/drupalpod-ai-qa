# Build Flow

DrupalPod AI QA automates the environment build in a predictable sequence.

## High-Level Order

1. Read the selected inputs such as Drupal type, AI version, test module, fork, and branch
2. Validate the combination and fill in defaults where possible
3. Resolve the correct Drupal and AI package versions
4. Build a manifest of the repos and versions to use
5. Clone the required repositories
6. Build the Drupal project and wire the cloned modules into it
7. Install Drupal
8. Apply the selected AI provider configuration (if applicable)

## What the Main Scripts Do

The main scripts live in `scripts/` and run in the following order.

### `fallback_setup.sh`

- Reads environment variables
- Applies defaults
- Validates the incoming combination of Drupal, AI, and module inputs

### `resolve_modules.sh`

- Resolves the concrete Drupal and AI package versions
- Determines which modules are compatible
- Writes the resolution result to `logs/ai-manifest.json`

### `clone_modules.sh`

- Clones the required AI ecosystem repositories into `repos/`
- Checks out the resolved refs, branches, or tags

### `composer_setup.sh`

- Builds the Drupal project
- Adds path repositories so the cloned modules are used by Drupal
- Prepares the final Composer setup before install/update

### `init.sh`

- Orchestrates the overall setup flow
- Runs the scripts above in sequence
- Continues into Drupal installation and environment setup

## Manifest and Repositories

The file `logs/ai-manifest.json` is the main resolution output.

It records which packages were selected, which were skipped, and which refs
were resolved. The cloned repos in `repos/` are then checked out based on that
manifest.

See the [Resolution Modes](resolution-modes.md) documentation for more details
on how versions are resolved and how compatibility is determined.