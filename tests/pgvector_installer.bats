#!/usr/bin/env bats

setup() {
    INSTALLER="$BATS_TEST_DIRNAME/../.devpanel/pgvector_installer.sh"
}

@test "configures PGDG only when the base image has not already done so" {
    run grep -Fq 'if ! grep -RqsE' "$INSTALLER"

    [ "$status" -eq 0 ]

    run grep -Fq 'https://apt.postgresql.org/pub/repos/apt' "$INSTALLER"

    [ "$status" -eq 0 ]
}

@test "still installs PostgreSQL 17 and pgvector" {
    run grep -F 'sudo apt-get install -y postgresql-17 postgresql-client-17 postgresql-17-pgvector' "$INSTALLER"

    [ "$status" -eq 0 ]
}
