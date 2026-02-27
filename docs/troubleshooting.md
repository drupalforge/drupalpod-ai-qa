# Troubleshooting

## Version conflict error

```
ERROR: Version Conflict
Test module 'ai_search' requires AI 2.0.x
But you explicitly configured DP_AI_MODULE_VERSION=1.2.x
```

Remove `DP_AI_MODULE_VERSION` to auto-detect, or set it to match.
If testing AI 2.x on CMS, set `DP_FORCE_DEPENDENCIES=1` so the local
Composer plugin can relax `drupal/ai` constraints.

## Module skipped warning

```
Incompatible: ai_search requires AI ^2.0, but we have AI 1.2.x
```

Expected behavior - the module is incompatible and correctly excluded. Still cloned to `repos/` for inspection.

## Build failures

Check `logs/init-*.log` for detailed output. Common issues:

- Git fetch failures (network/auth)
- Composer dependency conflicts
- Database connection problems

## Lenient mode not working

If you see errors like:
```
drupal/ai_context dev-1.0.x requires drupal/ai ^1.3 -> conflicts with your root composer.json require (2.0.x-dev)
```

Even with `DP_FORCE_DEPENDENCIES=1`, the lenient plugin might not be activated. Check:

1. **Plugin is installed to vendor/:**
   ```bash
   ls -la /tmp/tmp.*/vendor/drupalpod/ai-lenient-plugin
   ```

2. **No `--no-install` flag in plugin warm-up** (fixed in resolve_modules.sh):
   ```bash
   # Broken:
   composer update --no-install mglaman/composer-drupal-lenient drupalpod/ai-lenient-plugin

   # Fixed:
   composer update mglaman/composer-drupal-lenient drupalpod/ai-lenient-plugin
   ```

3. **Environment variables are set:**
   ```bash
   echo $DP_FORCE_DEPENDENCIES  # Should be "1"
   echo $DP_LENIENT_PACKAGES    # Should contain package patterns
   ```

The plugin must be extracted to `vendor/` (not just locked) for Composer to load and activate it.

## Debugging version detection

```bash
ddev ssh
cd repos/ai
git describe --tags
git branch -r --contains HEAD
```
