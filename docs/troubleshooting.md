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

## Debugging version detection

```bash
ddev ssh
cd repos/ai
git describe --tags
git branch -r --contains HEAD
```
