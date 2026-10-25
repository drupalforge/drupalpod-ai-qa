#!/usr/bin/env bats

setup() {
    cd "$BATS_TEST_TMPDIR"
    source "$BATS_TEST_DIRNAME/../scripts/lib/composer_utils.sh"
    mkdir -p "$BATS_TEST_TMPDIR/bin"
    export COMPOSER_ARGS="$BATS_TEST_TMPDIR/composer-args"
    cat > "$BATS_TEST_TMPDIR/bin/composer" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$COMPOSER_ARGS"
SH
    chmod +x "$BATS_TEST_TMPDIR/bin/composer"
    PATH="$BATS_TEST_TMPDIR/bin:$PATH"
}

@test "adds a path repository through Composer config" {
    add_path_repository "/project/repos/ai_search"

    mapfile -t args < "$COMPOSER_ARGS"
    [ "${args[0]}" = "config" ]
    [ "${args[1]}" = "--no-plugins" ]
    [ "${args[2]}" = "repositories.ai_search-git" ]
    [ "$(jq -r '.type' <<< "${args[3]}")" = "path" ]
    [ "$(jq -r '.url' <<< "${args[3]}")" = "/project/repos/ai_search" ]
    [ "$(jq -r '.options.symlink' <<< "${args[3]}")" = "true" ]
}
