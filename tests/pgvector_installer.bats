#!/usr/bin/env bats

setup() {
    INSTALLER="$BATS_TEST_DIRNAME/../.devpanel/pgvector_installer.sh"
}

@test "uses the PGDG repository configured by the base image" {
    run grep -F 'apt.postgresql.org' "$INSTALLER"

    [ "$status" -eq 1 ]
}

@test "still installs PostgreSQL 17 and pgvector" {
    run grep -F 'sudo apt-get install -y postgresql-17 postgresql-client-17 postgresql-17-pgvector' "$INSTALLER"

    [ "$status" -eq 0 ]
}
