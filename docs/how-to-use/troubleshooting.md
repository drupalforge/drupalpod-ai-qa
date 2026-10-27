# Troubleshooting

## Hosted workspace pauses too early

If a DrupalForge workspace pauses before the expected six-hour lifetime, flag
that with DrupalForge. That behavior is outside the normal repository flow.

## DrupalForge launch does not complete

If the hosted flow is not working, first check where it is failing:

- in the Chrome extension before launch
- on the generated environment screen in DrupalForge
- during DevPanel deployment
- after deployment, when opening the site or VS Code

The most common causes are:

- not being signed in to DrupalForge before launch
- missing or incorrect generated variables
- an issue fork or branch that does not match the selected version
- a build failure during deployment

If the environment reaches DevPanel, review the deployment status there first.
If it never gets that far, review the generated values in the extension and on
the DrupalForge launch screen.

## The site does not build correctly

If the Drupal site does not come up correctly, you can optionally open
browser-based VS Code and inspect the files in `logs/` to see where the build
failed.

If the problem looks like a DrupalPod AI QA issue, log it in the
[DrupalPod AI QA issue queue](https://www.drupal.org/project/issues/drupalpod_ai_qa).

When logging a build issue, please also include a screenshot from
[`drupalpod_build_info`](../how-it-works/custom-modules/drupalpod-build-info.md),
so it is clear what versions, refs, and targets were actually built.

For local setup issues, version-resolution problems, and log inspection, see
the [Developer Guide](../developer-guide.md).
