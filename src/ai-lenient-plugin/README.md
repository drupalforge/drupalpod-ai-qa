# DrupalPod AI Lenient Plugin

A lightweight Composer plugin that relaxes Drupal AI module version constraints when `DP_FORCE_DEPENDENCIES=1`.

## Purpose

This plugin enables QA testing of incompatible module combinations by relaxing version constraints during Composer's dependency resolution. It works alongside `mglaman/composer-drupal-lenient` to bypass semver restrictions.

## How It Works

The plugin subscribes to Composer's `PRE_POOL_CREATE` event and modifies package requirements before dependency resolution:

1. Checks if `DP_FORCE_DEPENDENCIES=1` is set
2. Reads lenient package patterns from `DP_LENIENT_PACKAGES` environment variable
3. For each package in the pool, relaxes matching requirements from specific versions (e.g., `^1.3`) to `*` (any version)

### Example

Without lenient mode:
```
ai_context requires drupal/ai ^1.3
→ Cannot install AI 2.0.x (conflict)
```

With lenient mode:
```
ai_context requires drupal/ai ^1.3  →  relaxed to  →  drupal/ai *
→ Can install AI 2.0.x (no conflict)
```

## Configuration

The plugin reads these environment variables:

- `DP_FORCE_DEPENDENCIES` - Must be `"1"` to activate
- `DP_LENIENT_PACKAGES` - Comma-separated list of package patterns to relax (supports wildcards)

Example:
```bash
export DP_FORCE_DEPENDENCIES=1
export DP_LENIENT_PACKAGES="drupal/ai,drupal/ai_*,drupal/ai_context"
```

### Wildcard Patterns

Patterns can include wildcards:
- `drupal/ai` - Exact match
- `drupal/ai_*` - Matches `drupal/ai_agents`, `drupal/ai_context`, etc.

## Installation

The plugin is installed automatically by `scripts/resolve_modules.sh` when `DP_FORCE_DEPENDENCIES=1`:

```bash
composer config repositories.ai-lenient-plugin \
    '{"type": "path", "url": "./src/ai-lenient-plugin", "options": {"symlink": true}}'
composer require drupalpod/ai-lenient-plugin:*@dev
composer update mglaman/composer-drupal-lenient drupalpod/ai-lenient-plugin
```

**Important:** The final `composer update` (without `--no-install`) is critical - it extracts the plugin to `vendor/` so Composer can load and activate it. Using `--no-install` will cause the plugin to be locked but never activated.

## Technical Details

- **Type:** `composer-plugin`
- **API Version:** `^2.0`
- **Event:** `PluginEvents::PRE_POOL_CREATE`
- **Activation:** Automatic when installed to `vendor/`

The plugin modifies `Link` objects in package requirements, replacing version constraints with a wildcard constraint (`*`) for matching packages.

## Inspiration

This plugin is inspired by [`mglaman/composer-drupal-lenient`](https://github.com/mglaman/composer-drupal-lenient), which provides broad Drupal ecosystem constraint relaxation. The AI lenient plugin focuses specifically on AI module constraints and is intentionally lightweight.

## License

MIT
