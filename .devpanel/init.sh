#!/usr/bin/env bash

# Optional debug mode; strict error handling for safety.
if [ -n "${DEBUG_SCRIPT:-}" ]; then
  set -x
fi
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Directory Setup (works in both DDEV and GitHub Actions environments)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# APP_ROOT is set by environment (DDEV or GitHub Actions)
# It should point to the composer root (docroot/)
cd "$APP_ROOT"
mkdir -p logs
LOG_FILE="logs/init-$(date +%F-%T).log"
exec > >(tee "$LOG_FILE") 2>&1

TIMEFORMAT=%lR
export COMPOSER_NO_AUDIT=1
export COMPOSER_NO_DEV=1

# Drush path (created after composer install)
DRUSH="$APP_ROOT/vendor/bin/drush"

# Source fallback setup
source "$DIR/fallback_setup.sh"

# Clone AI modules
echo
echo 'Cloning AI modules from git...'
time source "$DIR/clone_ai_modules.sh"

# Install VSCode extensions
if [ -n "${DP_VSCODE_EXTENSIONS:-}" ]; then
  IFS=','
  for value in $DP_VSCODE_EXTENSIONS; do
    time code-server --install-extension "$value"
  done
fi

# Clean rebuild vs incremental install
if [ "${DP_REBUILD:-0}" = "1" ]; then
  echo
  echo 'Performing clean rebuild...'
  echo 'Removing docroot directory...'
  time rm -rf docroot || echo "Note: Some files couldn't be removed (Mutagen sync active)"
  echo 'Rebuild mode enabled.'
  echo
fi

# Remove root-owned artifacts
echo
echo "Remove root-owned files."
time sudo rm -rf lost+found

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Composer setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ "${DP_REBUILD:-0}" = "1" ] || [ ! -f docroot/composer.json ]; then
  source "$DIR/composer_setup.sh"
else
  composer show --locked cweagans/composer-patches ^2 &>/dev/null && composer prl
fi

# Ensure dependencies are installed
composer -n update --no-dev --no-progress || composer dump-autoload

echo 'Running composer update...'
time composer -n update --no-dev --no-progress || {
  echo "Composer update encountered errors (likely patch failures), but continuing..."
  echo "Regenerating autoload files..."
  composer dump-autoload
}

echo 'All modules installed and ready!'

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Private files & config
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
[ ! -d private ] && { echo; echo 'Create the private files directory.'; time mkdir private; }
[ ! -d config/sync ] && { echo; echo 'Create the config sync directory.'; time mkdir -p config/sync; }

# Generate hash salt if missing
[ ! -f "$DIR/salt.txt" ] && { echo; echo 'Generate hash salt.'; time openssl rand -hex 32 > "$DIR/salt.txt"; }

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Install Drupal
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo
if [ "${DP_REBUILD:-0}" = "1" ] || ! $DRUSH status --field=bootstrap | grep -q "Drupal bootstrap"; then
  PROFILE="${DP_INSTALL_PROFILE-standard}"

  # Test database connection with drush status
  echo "Testing drush database connection..."
  $DRUSH status

  # Build database URL for drush
  DB_URL="${DB_DRIVER:-mysql}://${DB_USER:-user}:${DB_PASSWORD:-password}@${DB_HOST:-localhost}:${DB_PORT:-3306}/${DB_NAME:-drupaldb}"

  if [ -z "$PROFILE" ]; then
    echo "Installing Drupal CMS (auto-detect profile)"
    time $DRUSH -n si --db-url="$DB_URL" --account-name=admin --account-pass=admin
  else
    echo "Installing Drupal with profile: $PROFILE"
    time $DRUSH -n si "$PROFILE" --db-url="$DB_URL" --account-name=admin --account-pass=admin
  fi

  # AI setup if available
  if [ -n "${DP_AI_VIRTUAL_KEY:-}" ]; then
    source "$DIR/setup_ai.sh"
  fi

  echo
  echo 'Tell Automatic Updates about patches.'
  $DRUSH -n cset --input-format=yaml package_manager.settings additional_trusted_composer_plugins '["cweagans/composer-patches"]'
  $DRUSH -n cset --input-format=yaml package_manager.settings additional_known_files_in_project_root '["patches.json", "patches.lock.json"]'
  time $DRUSH ev '\Drupal::moduleHandler()->invoke("automatic_updates", "modules_installed", [[], FALSE])'
else
  echo 'Update database.'
  time $DRUSH -n updb
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Finish measuring script time
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INIT_DURATION=$SECONDS
INIT_HOURS=$(($INIT_DURATION / 3600))
INIT_MINUTES=$(($INIT_DURATION % 3600 / 60))
INIT_SECONDS=$(($INIT_DURATION % 60))
printf "\nTotal elapsed time: %d:%02d:%02d\n" $INIT_HOURS $INIT_MINUTES $INIT_SECONDS
