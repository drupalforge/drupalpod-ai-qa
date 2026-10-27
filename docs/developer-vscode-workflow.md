# Browser-Based VS Code Workflow

This page is for developers who want to use the hosted Visual Studio Code
environment in DrupalForge / DevPanel to inspect code, make changes, and push
work back to issue forks.

If you only need to open VS Code in the browser, use
[Working with Visual Studio Code in the Browser](how-to-use/vscode-in-browser.md).

## Find the Checked-Out Code

In the Visual Studio Code interface, the cloned repositories are available in
the `repos/` directory.

You can find them either:

- from the file explorer in the left sidebar
- from the integrated terminal

Examples:

```bash
cd repos/ai
```

```bash
cd repos/ai_image_alt_text
```

When you make code changes there, they affect the running environment directly.

## Push Changes Back to the Issue Fork

Configure your git identity in the terminal:

```bash
git config --global user.email "you@example.com"
git config --global user.name "Your Name"
```

Create a GitLab Personal Access Token with `write_repository` permission.

Then:

1. Change into the project repository inside `repos/`
2. Confirm the branch is the correct issue fork branch
3. Commit your changes
4. Run `git push <issue fork remote> <issue fork branch>`
5. Use the personal access token as the password when prompted

Example:

```bash
cd repos/ai
git status
git branch --show-current
git add .
git commit -m "Issue #1234567: Fix thing"
git push <issue fork remote> <issue fork branch>
```

## Using Drush

Run Drush from the project root:

```bash
./docroot/vendor/bin/drush
```

## Running PHPUnit Tests

Copy `docroot/web/core/phpunit.xml.dist` to `phpunit.xml`, then open both
`phpunit.xml` and `docroot/web/core/sites/default/settings.php`.

It may help to use the editor's side-by-side view so you can compare the files
while editing the PHPUnit settings.

In `phpunit.xml`:

- change the `bootstrap` value to `docroot/web/core/tests/bootstrap.php`
- change `SIMPLETEST_BASE_URL` to `http://localhost`
- change `SIMPLETEST_DB` to match the database connection values from
  `settings.php`

The database string should look like:

```text
mysql://username:password@host:port/database_name
```

Replace:

- `username` with the username value
- `password` with the password value
- `host` with the host value
- `port` with the port value
- `database_name` with the database value

Then, from `/var/www/html`, run PHPUnit with the local config file:

```bash
docroot/vendor/bin/phpunit -c phpunit.xml <web/path/to/test>
```

Example:

```bash
docroot/vendor/bin/phpunit -c phpunit.xml web/core/modules/node/tests/src/Kernel/ConfigActionTest.php
```
