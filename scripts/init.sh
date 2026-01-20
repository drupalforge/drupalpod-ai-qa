#!/usr/bin/env bash

# Optional debug mode; strict error handling for safety.
if [ -n "${DEBUG_SCRIPT:-}" ]; then
  set -x
fi
set -eu -o pipefail

# Predefine optional env vars for set -u safety.
: "${DEBUG_SCRIPT:=}"
: "${DP_REBUILD:=}"
: "${DP_VSCODE_EXTENSIONS:=}"
: "${DP_INSTALL_PROFILE:=}"
: "${DP_AI_VIRTUAL_KEY:=}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Directory Setup (works in both DDEV and GitHub Actions environments).
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Load common utilities.
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
init_common

# APP_ROOT is set by environment (DDEV or GitHub Actions).
# It should point to the composer root (docroot/).
# Start in PROJECT_ROOT so we can remove docroot if needed.
cd "$PROJECT_ROOT"
LOG_FILE="logs/init-$(date +%F-%T).log"
exec > >(tee "$LOG_FILE") 2>&1

TIMEFORMAT=%lR
export COMPOSER_NO_AUDIT=1

# Source fallback setup. This script sets default
# env vars if they are missing.
source "$SCRIPT_DIR/fallback_setup.sh"

# Resolve module versions via Composer first to ensure
# what we are testing works together, unless explicit
# module versions are being tested.
echo
echo 'Resolving module dependencies via Composer...'
time source "$SCRIPT_DIR/resolve_modules.sh"

# Clone modules from source so they can be symlinked
# into the composer project.
echo
echo 'Cloning AI modules from git...'
time source "$SCRIPT_DIR/clone_modules.sh"

# Install VSCode extensions.
if [ -n "${DP_VSCODE_EXTENSIONS:-}" ]; then
  IFS=','
  for value in $DP_VSCODE_EXTENSIONS; do
    time code-server --install-extension "$value"
  done
fi

# Clean rebuild vs incremental install.
# DP rebuild is only intended to be used
# in development environments.
if [ "${DP_REBUILD:-0}" = "1" ]; then
  echo
  echo 'Performing clean rebuild...'
  echo 'Removing docroot directory...'
  # Make sites/default writable before removal (Drupal makes it read-only for security)
  if [ -d "$APP_ROOT/web/sites/default" ]; then
    chmod -R u+w "$APP_ROOT/web/sites/default" 2>/dev/null || true
  fi
  time rm -rf docroot || echo "Note: Some files couldn't be removed (Mutagen sync active)"
  echo 'Rebuild mode enabled.'
  echo
fi

# Ensure APP_ROOT exists and cd into it.
mkdir -p "$APP_ROOT"
cd "$APP_ROOT"

# Remove root-owned artifacts (avoid sudo; ignore if not present).
echo
echo "Remove root-owned files."
rm -rf lost+found 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Composer setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ "${DP_REBUILD:-0}" = "1" ] || [ ! -f docroot/composer.json ]; then
  source "$SCRIPT_DIR/composer_setup.sh"
else
  composer show --locked cweagans/composer-patches ^2 &>/dev/null && composer prl
fi

# Ensure dependencies are installed.
echo 'Running composer update...'
time composer -n update --prefer-dist --no-progress || {
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

# Generate hash salt if missing.
[ ! -f "$DEV_PANEL_DIR/salt.txt" ] && { echo; echo 'Generate hash salt.'; time openssl rand -hex 32 > "$DEV_PANEL_DIR/salt.txt"; }

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Install Drupal
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo
if [ "${DP_REBUILD:-0}" = "1" ] || ! $DRUSH status --field=bootstrap | grep -q "Drupal bootstrap"; then
  PROFILE="${DP_INSTALL_PROFILE-standard}"

  # Test database connection with drush status.
  echo "Testing drush database connection..."
  $DRUSH status

  # Build database URL for drush.
  DB_URL="${DB_DRIVER:-mysql}://${DB_USER:-user}:${DB_PASSWORD:-password}@${DB_HOST:-localhost}:${DB_PORT:-3306}/${DB_NAME:-drupaldb}"

  # Install Drupal.
  if [ -z "$PROFILE" ]; then
    echo "Installing Drupal CMS (auto-detect profile)"
    time $DRUSH -n si --db-url="$DB_URL" --account-name=admin --account-pass=admin
  else
    echo "Installing Drupal with profile: $PROFILE"
    time $DRUSH -n si "$PROFILE" --db-url="$DB_URL" --account-name=admin --account-pass=admin
  fi

  # AI setup (if available).
  if [ -n "${DP_AI_VIRTUAL_KEY:-}" ]; then
    source "$SCRIPT_DIR/setup_ai.sh"
  fi

  # Enable AI modules.
  source "$SCRIPT_DIR/enable_ai_modules.sh"

  # Run any post-install tasks.
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
# Git status summary (cloned modules)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# This is mainly for tracking which versions were cloned
# during the init process, especially during testing.
if [ -d "$PROJECT_ROOT/repos" ]; then
  echo
  echo "Git status for cloned modules:"
  for repo in "$PROJECT_ROOT"/repos/*; do
    [ -d "$repo" ] || continue
    if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      name="$(basename "$repo")"
      echo
      echo "[$name]"
      git -C "$repo" status -sb
      git -C "$repo" describe --tags --always --dirty
    fi
  done
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Finish measuring script time
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
INIT_DURATION=$SECONDS
INIT_HOURS=$(($INIT_DURATION / 3600))
INIT_MINUTES=$(($INIT_DURATION % 3600 / 60))
INIT_SECONDS=$(($INIT_DURATION % 60))
printf "\nTotal elapsed time: %d:%02d:%02d\n" $INIT_HOURS $INIT_MINUTES $INIT_SECONDS

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Log into Drupal site with admin:admin user
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
$DRUSH uli --name=admin
