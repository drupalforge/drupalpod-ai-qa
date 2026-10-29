#!/usr/bin/env bats

setup() {
    INSTALLER="$BATS_TEST_DIRNAME/../.devpanel/pgvector_installer.sh"
}

@test "refreshes APT indexes and checks package candidates before configuring PGDG" {
    run grep -Fq 'time sudo apt-get update' "$INSTALLER"

    [ "$status" -eq 0 ]

    run grep -Fq 'apt-cache policy "$package"' "$INSTALLER"

    [ "$status" -eq 0 ]

    run grep -Fq 'if [ "$ID" = debian ]; then' "$INSTALLER"

    [ "$status" -eq 0 ]
}

@test "adds official PGDG and refreshes indexes when a required package is unavailable" {
    run grep -Fq 'https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main' "$INSTALLER"

    [ "$status" -eq 0 ]

    [ "$(grep -Fc 'time sudo apt-get update' "$INSTALLER")" -eq 2 ]
}

@test "still installs PostgreSQL 17 and pgvector" {
    run grep -F 'sudo apt-get install -y postgresql-17 postgresql-client-17 postgresql-17-pgvector' "$INSTALLER"

    [ "$status" -eq 0 ]
}
