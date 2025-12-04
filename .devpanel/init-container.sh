#!/bin/bash
# ---------------------------------------------------------------------
# Copyright (C) 2025 DevPanel
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as
# published by the Free Software Foundation version 3 of the
# License.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# For GNU Affero General Public License see <https://www.gnu.org/licenses/>.
# ----------------------------------------------------------------------

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Directory Setup (works in both DDEV and GitHub Actions environments)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Find the .devpanel directory (where this script lives)
DEVPANEL_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Project root is one level up from .devpanel
PROJECT_ROOT="$(dirname "$DEVPANEL_DIR")"
# APP_ROOT is the composer root (from environment or default to PROJECT_ROOT)
APP_ROOT="${APP_ROOT:-$PROJECT_ROOT}"

# Define drush command
DRUSH="$APP_ROOT/vendor/bin/drush"

#== Import database
if [[ $(mysql -h$DB_HOST -P$DB_PORT -u$DB_USER -p$DB_PASSWORD $DB_NAME -e "show tables;") == '' ]]; then
  if [[ -f "$APP_ROOT/.devpanel/dumps/db.sql.gz" ]]; then
    echo  'Import mysql file ...'
    $DRUSH sqlq --file="$APP_ROOT/.devpanel/dumps/db.sql.gz" --file-delete
  fi
fi

if [[ -n "$DB_SYNC_VOL" ]]; then
  if [[ ! -f "/var/www/build/.devpanel/init-container.sh" ]]; then
    echo  'Sync volume...'
    sudo chown -R 1000:1000 /var/www/build
    rsync -av --delete --delete-excluded $APP_ROOT/ /var/www/build
  fi
fi

$DRUSH -n updb
echo
echo 'Run cron.'
$DRUSH cron
