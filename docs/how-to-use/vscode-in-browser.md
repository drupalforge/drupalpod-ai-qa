# Working with Visual Studio Code in the Browser

This page covers the basic hosted Visual Studio Code access flow available from
DrupalForge / DevPanel after an environment has been deployed.

## Open Visual Studio Code in the Browser

From the Application Summary page, under `Start VSCode In Browser`:

1. Copy the VS Code password
2. Follow the `Open Application` link
3. Paste the password into the `Welcome to code-server` page
4. Click `SUBMIT`

The `Open Application` link and password can also be shared if you need a
shared workspace.

## What You Can Do There

In browser-based VS Code, you can:

- inspect the Drupal site in `docroot/`
- inspect git modules in `repos/`
- use the terminal
- look in `logs/` if a build fails

If you want the full developer workflow for browser-based VS Code, including
git, Drush, and PHPUnit, see
[Browser-Based VS Code Workflow](../developer-vscode-workflow.md).
