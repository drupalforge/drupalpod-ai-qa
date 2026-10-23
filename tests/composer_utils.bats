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

@test "adds a path repository to the front of an existing repository array" {
    chmod 644 composer.json

    add_path_repository "/project/repos/new-module"

    [ "$(jq '.repositories | type' composer.json)" = '"array"' ]
    [ "$(jq -r '.repositories[0].type' composer.json)" = "path" ]
    [ "$(jq -r '.repositories[0].url' composer.json)" = "/project/repos/new-module" ]
    [ "$(jq -r '.repositories[0].options.symlink' composer.json)" = "true" ]
    [ "$(jq -r '.repositories[1].name' composer.json)" = "local-module" ]
    [ "$(jq -r '.repositories[2].name' composer.json)" = "drupal" ]
    [ "$(stat -c '%a' composer.json)" = "644" ]
}

@test "normalizes Composer 2.7 keyed repositories to a valid list" {
    cat > composer.json <<'JSON'
{
  "repositories": {
    "drupal": {
      "name": "drupal",
      "type": "composer",
      "url": "https://packages.drupal.org/8"
    },
    "ai_search-git": {
      "name": "ai_search-git",
      "type": "path",
      "url": "/project/repos/ai_search",
      "options": {"symlink": true}
    }
  }
}
JSON

    add_path_repository "/project/repos/new-module"

    [ "$(jq '.repositories | type' composer.json)" = '"array"' ]
    [ "$(jq '.repositories | length' composer.json)" -eq 3 ]
    [ "$(jq -r '.repositories[0].url' composer.json)" = "/project/repos/new-module" ]
    [ "$(jq -e 'all(.repositories[1:][]; has("name") | not)' composer.json)" = "true" ]
    [ "$(jq -r '.repositories[1].url' composer.json)" = "https://packages.drupal.org/8" ]
    [ "$(jq -r '.repositories[2].url' composer.json)" = "/project/repos/ai_search" ]
}

@test "adds a path repository when repositories are absent" {
    echo '{}' > composer.json

    add_path_repository "/project/repos/new-module"

    [ "$(jq '.repositories | length' composer.json)" -eq 1 ]
    [ "$(jq -r '.repositories[0].url' composer.json)" = "/project/repos/new-module" ]
}
