#!/usr/bin/env bats

setup() {
    PROJECT_ROOT="$(cd "$BATS_TEST_DIRNAME/.." && pwd)"
    SOURCE_DIR="$BATS_TEST_TMPDIR/apt-sources"
    mkdir -p "$SOURCE_DIR"

    eval "$(sed -n '/^pgdg_repository_configured()/,/^}/p' "$PROJECT_ROOT/.devpanel/pgvector_installer.sh")"
}

@test "detects an active PGDG deb source" {
    source_file="$SOURCE_DIR/pgdg.list"
    echo 'deb [signed-by=/usr/share/keyrings/pgdg.gpg] https://apt.postgresql.org/pub/repos/apt trixie-pgdg main' > "$source_file"

    run pgdg_repository_configured "$source_file"

    [ "$status" -eq 0 ]
}

@test "detects an active PGDG deb822 source" {
    source_file="$SOURCE_DIR/pgdg.sources"
    cat > "$source_file" <<'EOF'
Types: deb
URIs: https://apt.postgresql.org/pub/repos/apt
Suites: trixie-pgdg
Components: main
EOF

    run pgdg_repository_configured "$source_file"

    [ "$status" -eq 0 ]
}

@test "ignores a commented PGDG source" {
    source_file="$SOURCE_DIR/pgdg.list"
    echo '# deb https://apt.postgresql.org/pub/repos/apt trixie-pgdg main' > "$source_file"

    run pgdg_repository_configured "$source_file"

    [ "$status" -ne 0 ]
}
