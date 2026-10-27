# Developer Guide

This guide is for developers who want to inspect the generated environment,
switch branches in cloned repositories, make changes locally, and commit work
back to upstream forks.

If you only want to launch and use an environment, use the
[Step-by-Step Guide](how-to-use/step-by-step-guide.md) instead.

## What Is Different for Developers

DrupalPod AI QA does not just install released packages. It resolves versions,
clones module repositories into `repos/`, and symlinks them into the generated
Drupal codebase.

That means you can:

- Inspect the exact repositories used for the build
- Switch branches inside cloned module repos
- Make code changes directly in those repos
- Commit and push changes back to your fork

## Typical Use Cases

Use this guide if you need to:

- Review the checked-out code for a built environment
- Test a different branch inside one of the cloned repos
- Make a code change and verify it locally
- Push follow-up work back to an issue fork or personal fork
- Understand when a code change requires a rebuild versus a normal edit-and-refresh workflow

## Key Directories

- `repos/` contains the cloned AI project repositories
- `docroot/` contains the generated Drupal project
- `logs/ai-manifest.json` records the resolved versions and selected repos
- `custom_modules/` contains repo-managed custom Drupal modules for this project

## Choose a Development Environment

There are two main ways to work in the code:

- Use [Local DDEV Guide](how-to-use/local-ddev-guide.md) if you want to run the project on your own machine
- Use the browser-based VS Code option in DrupalForge if you want to inspect or edit the code in a hosted environment

For the hosted browser workflow, see
[Browser-Based VS Code Workflow](developer-vscode-workflow.md).

## Before You Change Branches

Check the current repo state before switching branches:

```bash
cd repos/ai
git status
git remote -v
git branch --show-current
```

This helps you avoid changing branches with uncommitted work in place.

## Find the Checked-Out Repositories

After the environment is built, inspect the cloned repos:

```bash
ls repos
```

To inspect the resolved plan:

```bash
cat logs/ai-manifest.json
```

That manifest tells you which modules were selected, skipped, or pinned during
resolution.

## Switch to a Different Branch in a Repo

Move into the repository you want to work on and use normal git commands.

Example:

```bash
cd repos/ai
git status
git branch -a
git checkout 1.4.x
```

Example for a test module:

```bash
cd repos/ai_image_alt_text
git remote -v
git fetch origin
git checkout 1.0.x
```

## Work on Your Fork

If you need to commit changes back to your own fork:

```bash
cd repos/ai_image_alt_text
git remote -v
git remote add fork git@git.drupalcode.org:issue/ai_image_alt_text-1234567.git
git fetch fork
git checkout -b 1234567-fix-thing fork/1234567-fix-thing
```

Then commit normally:

```bash
git add .
git commit -m "Issue #1234567: Fix thing"
git push fork HEAD
```

## Important Workflow Detail

Changes in `repos/` are live in the running Drupal site because those
repositories are wired into the generated codebase through path repos and
symlinks. You do not need to copy files back into `docroot/`.

## When to Rebuild

You usually do not need a full rebuild when you are only editing code in an
already-cloned repo.

You do need to rebuild when you change inputs such as:

- `DP_TEST_MODULE`
- `DP_AI_MODULE_VERSION`
- `DP_AI_ISSUE_FORK`
- `DP_AI_ISSUE_BRANCH`
- `DP_TEST_MODULE_ISSUE_FORK`
- `DP_TEST_MODULE_ISSUE_BRANCH`
- `DP_STARTER_TEMPLATE`

Apply those changes with:

```bash
ddev restart
```

## Commit and Push Guidance

Before pushing changes back:

- Confirm you are in the correct repository under `repos/`
- Confirm the branch name matches the issue or merge request workflow
- Check `git remote -v` so you do not push to the wrong remote
- Use `git diff` and `git status` before committing

## Common Developer Tasks

### Check which branch a repo is on

```bash
cd repos/ai
git branch --show-current
git describe --tags
```

### Inspect remotes before pushing

```bash
cd repos/ai_agents
git remote -v
```

### Create a patch or compare your work

```bash
git diff
git status
```

## Troubleshooting

### Local DDEV permission or authentication issues

If local setup fails during git operations or repo access, run:

```bash
ddev auth ssh
```

Then restart the environment:

```bash
ddev restart
```

### Version conflict error

```
ERROR: Version Conflict
Test module 'ai_search' requires AI 2.0.x
But you explicitly configured DP_AI_MODULE_VERSION=1.2.x
```

Remove `DP_AI_MODULE_VERSION` to auto-detect, or set it to match.
If testing AI 2.x on CMS, set `DP_FORCE_DEPENDENCIES=1` so the local
Composer plugin can relax `drupal/ai` constraints.

### Module skipped warning

```
Incompatible: ai_search requires AI ^2.0, but we have AI 1.2.x
```

Expected behavior. The module is incompatible and correctly excluded, while
still being cloned into `repos/` for inspection.

### Build failures

Check `logs/init-*.log` for detailed output. Common issues include:

- Git fetch failures
- Composer dependency conflicts
- Database connection problems

### Lenient mode not working

If you see errors like:

```
drupal/ai_context dev-1.0.x requires drupal/ai ^1.3 -> conflicts with your root composer.json require (2.0.x-dev)
```

Even with `DP_FORCE_DEPENDENCIES=1`, the lenient plugin might not be
activated. Check:

1. Plugin is installed to `vendor/`:

```bash
ls -la /tmp/tmp.*/vendor/drupalpod/ai-lenient-plugin
```

2. No `--no-install` flag in plugin warm-up:

```bash
composer update mglaman/composer-drupal-lenient drupalpod/ai-lenient-plugin
```

3. Environment variables are set:

```bash
echo $DP_FORCE_DEPENDENCIES
echo $DP_LENIENT_PACKAGES
```

The plugin must be extracted to `vendor/` and not just locked in the Composer
metadata.

### Debugging version detection

```bash
ddev ssh
cd repos/ai
git describe --tags
git branch -r --contains HEAD
```

## Related Technical Docs

- [Browser-Based VS Code Workflow](developer-vscode-workflow.md) for hosted editing, git, Drush, and PHPUnit
- [Development](development.md) for script architecture and repo behavior
- [Testing](testing.md) for BATS and scenario validation
- [Local DDEV Guide](how-to-use/local-ddev-guide.md) for environment setup and override examples
