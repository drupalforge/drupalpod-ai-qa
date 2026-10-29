#!/usr/bin/env bats

setup() {
    INSTALLER="$BATS_TEST_DIRNAME/../.devpanel/pgvector_installer.sh"
}

@test "configures PGDG for Debian Bullseye and Bookworm" {
    run grep -Fq 'time sudo apt-get update' "$INSTALLER"

    [ "$status" -eq 0 ]

    run grep -Fq '[[ "$VERSION_CODENAME" == bullseye || "$VERSION_CODENAME" == bookworm ]]' "$INSTALLER"

    [ "$status" -eq 0 ]

    run grep -Fq 'https://apt.postgresql.org/pub/repos/apt ${VERSION_CODENAME}-pgdg main' "$INSTALLER"

    [ "$status" -eq 0 ]
}

@test "does not query package candidates to select the PostgreSQL repository" {
    run grep -Fq 'apt-cache policy' "$INSTALLER"

    [ "$status" -eq 1 ]

    [ "$(grep -Fc 'time sudo apt-get update' "$INSTALLER")" -eq 2 ]
}

@test "still installs PostgreSQL 17 and pgvector" {
    run grep -F 'sudo apt-get install -y postgresql-17 postgresql-client-17 postgresql-17-pgvector' "$INSTALLER"

    [ "$status" -eq 0 ]
}
