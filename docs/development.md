# Development

Contributor notes for working on scripts, tests, and flows.

## Scripts

Key scripts live in `scripts/`:

- `scripts/init.sh` — main entry point
- `scripts/fallback_setup.sh` — defaults + validation
- `scripts/resolve_modules.sh` — Composer resolution plan
- `scripts/clone_modules.sh` — git checkouts based on the plan
- `scripts/composer_setup.sh` — build composer.json + path repos

DevPanel expects an init entry point at `.devpanel/init.sh`, which forwards
to `scripts/init.sh`.

## DevPanel Scripts

The `.devpanel/` scripts are based on the upstream DrupalPod fork:
`https://github.com/shaal/DrupalPod`. Most files there are unchanged from the
base fork; this repo focuses its changes under `scripts/`.

GitHub Actions and image build automation live in the upstream DrupalPod
tooling and are reused here with minimal adjustments.

## Docker Images

Images are built by GitHub Actions:

- `.github/workflows/docker-publish-images.yml` orchestrates builds.
- `.github/workflows/docker-publish-image.yml` is the reusable build template.

Current image matrix:

- `drupalforge/drupalpod-ai-qa:php-8.3-cms` (CMS, latest)
- `drupalforge/drupalpod-ai-qa:php-8.3-core` (core, latest)
- `drupalforge/drupalpod-ai-qa:php-8.2-core` (core, Drupal 10.4.x)
- `drupalforge/drupalpod-ai-qa:latest` (alias for php-8.3-cms)
- `drupalforge/drupalpod-ai-qa:core` (alias for php-8.3-core)

## Testing

Test suites:

- BATS unit/integration tests: `npm test`
- Scenario runner: `./tests/run-scenarios.sh`

See `docs/testing.md` for details and conventions.

## Configuration Files

- `.ddev/config.drupal.yaml`: local overrides
- `.ddev/config.drupalpod.yaml`: DevPanel/DrupalForge overrides

Avoid editing `.ddev/config.yaml` directly.

## Git Repos

AI modules are cloned into `repos/` and symlinked into `docroot/`.
If a module is enabled but not a git repo, `init.sh` warns so you can
track missing checkouts.
