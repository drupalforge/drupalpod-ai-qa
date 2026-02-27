#!/usr/bin/env bash
# Composer operation utilities for DrupalPod AI QA scripts.
# Provides safe composer operations with backup/restore and lenient mode configuration.

# Backup composer.json and composer.lock files.
# Call before attempting risky composer operations.
backup_composer() {
    cp composer.json composer.json.bak
    cp composer.lock composer.lock.bak
}

# Restore composer.json and composer.lock from backup.
# Call after a failed composer operation to roll back.
restore_composer() {
    mv composer.json.bak composer.json
    mv composer.lock.bak composer.lock
}

# Clean up composer backup files.
# Call after a successful composer operation.
cleanup_composer_backup() {
    rm -f composer.json.bak composer.lock.bak
}

# Try a composer operation with automatic backup/restore.
# Usage: try_composer_operation "operation description" command args...
# Returns 0 on success, 1 on failure.
try_composer_operation() {
    local description="$1"
    shift

    echo "  ${description}..."
    backup_composer

    if "$@" 2>/dev/null; then
        cleanup_composer_backup
        return 0
    else
        restore_composer
        return 1
    fi
}

# Enable composer-drupal-lenient with a list of allowed packages.
configure_lenient_mode() {
    local packages=("$@")

    if [ "${#packages[@]}" -eq 0 ]; then
        return
    fi

    local allow_list_json
    allow_list_json=$(build_json_array "${packages[@]}")

    composer config --no-plugins allow-plugins.mglaman/composer-drupal-lenient true
    composer require --prefer-dist -n --no-update "mglaman/composer-drupal-lenient:^1.0"
    composer config --json extra.drupal-lenient.allowed-list "$allow_list_json"
}
