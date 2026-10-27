# Resolution Modes

The resolver can work in different modes depending on which version inputs are
explicitly set.

These mode numbers are written into the build metadata and shown by
`drupalpod_build_info`, alongside the `compatibility` value.

## Mode 1: AI or Test Target Pinned, Drupal Auto-Detects

Mode `1` is used when the AI side is pinned but Drupal is not.

This includes cases where you set:

- `DP_AI_MODULE_VERSION`
- `DP_TEST_MODULE_VERSION`
- `DP_AI_ISSUE_BRANCH`
- `DP_TEST_MODULE_ISSUE_BRANCH`

In this mode, the resolver first tries a normal strict Composer solve. If that
fails because of a dependency conflict, it can escalate to Mode `4`.

## Mode 2: Drupal Pinned, AI Auto-Detects

Mode `2` is used when Drupal is pinned but the AI side is not.

This applies when `DP_VERSION` is set, but no AI-side version or issue branch
is acting as a pin.

In this mode, the resolver keeps the Drupal selection fixed and resolves the AI
side around it.

## Mode 3: Full Auto-Detect

Mode `3` is used when neither Drupal nor the AI side is pinned.

This is the full auto-detect path. The resolver chooses the most appropriate
combination based on the selected starter template and the packages being
requested.

## Mode 4: Drupal and AI Both Pinned

Mode `4` is used when both sides are pinned.

This applies when:

- Drupal is pinned through `DP_VERSION`
- the AI side is pinned through an explicit version or issue branch

If `DP_FORCE_DEPENDENCIES=1`, this mode can use the forced lenient resolution
path. If `DP_FORCE_DEPENDENCIES=0`, conflicting pinned combinations fail with
an unresolvable error.

## Compatibility Values

The build metadata also records a `compatibility` value. This is what shows up
in build info entries such as `compatibility clean, mode 1`.

The main values are:

- `clean`: the resolver completed without needing forced lenient resolution
- `forced`: the resolver had to use the forced lenient path in Mode `4`
- `error_unresolvable`: the selected combination could not be resolved
- `error_infra`: the build failed because of an infrastructure or network-type problem

## Compatibility and Skipping

Not every optional extra module will work with every AI version.

When `DP_EXTRA_MODULES` is set, DrupalPod AI QA treats those modules as
best-effort extras. After the base AI version is resolved, it checks each
requested extra module for compatibility.

If an extra module does not fit the resolved combination, it is skipped and
recorded in the manifest as a skipped package.

This compatibility check is strict for extras: the resolver disables plugins
for that check rather than using the lenient path.

## Lenient Dependency Resolution

`DP_FORCE_DEPENDENCIES=1` enables lenient dependency handling for the forced
resolution path.

This is useful when QA needs to test combinations that are not yet fully aligned
with declared Composer constraints, such as a module branch being tested
against a newer AI base version.

Two Composer plugins are used to support this workflow:

- `mglaman/composer-drupal-lenient`
- `drupalpod/ai-lenient-plugin`

The local `ai-lenient-plugin` lives in `src/ai-lenient-plugin/` and is specific
to this repository.

In practice, this helps the resolver:

- Relax certain `drupal/ai` version constraints
- Test combinations that are useful for QA even when upstream Composer metadata is not yet aligned
- Keep moving when the goal is validation rather than strict semver enforcement

If you want strict compatibility behavior instead, set `DP_FORCE_DEPENDENCIES=0`.

## Why Modes and Lenient Handling Matter

The selected resolution mode and the lenient setting together determine how
much the tool should auto-detect versus how much it should obey explicit
version input.

That is why the same issue may build differently depending on whether:

- you leave the version fields empty
- you pin AI explicitly
- you pin Drupal explicitly
- you provide issue forks and branches
- you allow lenient dependency resolution
