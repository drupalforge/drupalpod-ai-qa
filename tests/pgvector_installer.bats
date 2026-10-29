#!/usr/bin/env bats

setup() {
    INSTALLER="$BATS_TEST_DIRNAME/../.devpanel/pgvector_installer.sh"
}

@test "configures PGDG for Debian releases below 13 using the official script" {
    run grep -Fq 'time sudo apt-get update' "$INSTALLER"

    [ "$status" -eq 0 ]

    run grep -Fq '(( DEBIAN_VERSION < 13 ))' "$INSTALLER"

    [ "$status" -eq 0 ]

    run grep -Fq '/usr/share/postgresql-common/pgdg/apt.postgresql.org.sh' "$INSTALLER"

    [ "$status" -eq 0 ]
}

@test "updates APT indexes after configuring the official repository" {
    [ "$(grep -Fc 'time sudo apt-get update' "$INSTALLER")" -eq 2 ]

    run grep -Fq 'apt-cache policy' "$INSTALLER"

    [ "$status" -eq 1 ]
}

@test "still installs PostgreSQL 17 and pgvector" {
    run grep -F 'sudo apt-get install -y postgresql-17 postgresql-client-17 postgresql-17-pgvector' "$INSTALLER"

    [ "$status" -eq 0 ]
}
