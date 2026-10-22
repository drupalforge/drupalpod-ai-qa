#!/usr/bin/env bats

setup() {
    cd "$BATS_TEST_TMPDIR"
    source "$BATS_TEST_DIRNAME/../scripts/lib/composer_utils.sh"
    cat > composer.json <<'JSON'
{
  "repositories": [
    {
      "name": "local-module",
      "type": "path",
      "url": "/project/repos/module",
      "options": {"symlink": true}
    },
    {
      "name": "drupal",
      "type": "composer",
      "url": "https://packages.drupal.org/8"
    }
  ]
}
JSON
}

@test "suspends path repositories for the command and restores them" {
    chmod 644 composer.json

    check_without_path_repositories() {
        jq -e 'all(.repositories[]; .type != "path")' composer.json >/dev/null
    }

    run_without_path_repositories check_without_path_repositories

    [ "$(jq '[.repositories[] | select(.type == "path")] | length' composer.json)" -eq 1 ]
    [ "$(stat -c '%a' composer.json)" = "644" ]
}

@test "restores path repositories when the command fails" {
    fail_after_checking_repositories() {
        jq -e 'all(.repositories[]; .type != "path")' composer.json >/dev/null
        return 17
    }

    run run_without_path_repositories fail_after_checking_repositories

    [ "$status" -eq 17 ]
    [ "$(jq '[.repositories[] | select(.type == "path")] | length' composer.json)" -eq 1 ]
}

@test "runs commands directly when there are no path repositories" {
    jq 'del(.repositories[0])' composer.json > no-path-repositories.json
    mv no-path-repositories.json composer.json
    check_command() {
        jq -e 'all(.repositories[]; .type != "path")' composer.json >/dev/null
    }

    run_without_path_repositories check_command

    [ "$(jq '.repositories | length' composer.json)" -eq 1 ]
}
