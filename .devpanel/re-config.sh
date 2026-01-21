#!/bin/bash
# ---------------------------------------------------------------------
# Copyright (C) 2021 DevPanel
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
# APP_ROOT and COMPOSER_ROOT are set by environment (DDEV or GitHub Actions)
: "${COMPOSER_ROOT:=${APP_ROOT}/docroot}"
DRUSH="$COMPOSER_ROOT/vendor/bin/drush"
STATIC_FILES_PATH="$WEB_ROOT/sites/default/files/"
SETTINGS_FILES_PATH="$WEB_ROOT/sites/default/settings.php"

#Create static directory
if [ ! -d "$STATIC_FILES_PATH" ]; then
  mkdir -p $STATIC_FILES_PATH
fi


#== Composer install.
if [[ -f "$COMPOSER_ROOT/composer.json" ]]; then
  cd $COMPOSER_ROOT && composer install
fi

#== Generate hash salt
echo 'Generate hash salt ...'
DRUPAL_HASH_SALT=$(openssl rand -hex 32);
echo $DRUPAL_HASH_SALT > $COMPOSER_ROOT/.devpanel/salt.txt


# Securing file permissions and ownership
# https://www.drupal.org/docs/security-in-drupal/securing-file-permissions-and-ownership
[[ ! -d $STATIC_FILES_PATH ]] && sudo mkdir --mode 775 $STATIC_FILES_PATH || sudo chmod 775 -R $STATIC_FILES_PATH

#== Extract static files
if [[ $(mysql -h$DB_HOST -P$DB_PORT -u$DB_USER -p$DB_PASSWORD $DB_NAME -e "show tables;") == '' ]]; then
  if [[ -f "$COMPOSER_ROOT/.devpanel/dumps/files.tgz" ]]; then
    echo  'Extract static files ...'
    sudo mkdir -p $STATIC_FILES_PATH
    sudo tar xzf "$COMPOSER_ROOT/.devpanel/dumps/files.tgz" -C $STATIC_FILES_PATH
    sudo rm -rf $COMPOSER_ROOT/.devpanel/dumps/files.tgz
  fi

  #== Import mysql files
  if [[ -f "$COMPOSER_ROOT/.devpanel/dumps/db.sql.gz" ]]; then
    echo  'Import mysql file ...'
    "$DRUSH" sqlq --file="$COMPOSER_ROOT/.devpanel/dumps/db.sql.gz" --file-delete
  fi
fi
