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
: "${DP_NO_DEV:=}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Directory Setup (works in both DDEV and GitHub Actions environments).
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Load common utilities.
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/bootstrap.sh"
source "$SCRIPT_DIR/lib/resolve_mode.sh"

# APP_ROOT is set by environment (DDEV or GitHub Actions) as the repo root.
# COMPOSER_ROOT points to the composer root (docroot/).
# Start in PROJECT_ROOT so we can remove docroot if needed.
cd "$PROJECT_ROOT"
LOG_FILE="logs/init-$(date +%F-%T).log"
exec > >(tee "$LOG_FILE") 2>&1

TIMEFORMAT=%lR
export COMPOSER_NO_AUDIT=1

# Prevent concurrent init runs against the same workspace.
exec 200>"$LOG_DIR/init.lock"
if ! flock -n 200; then
  log_error "Another init.sh run is already in progress."
  exit 1
fi

# Source fallback setup. This script sets default
# env vars if they are missing.
source "$SCRIPT_DIR/fallback_setup.sh"

run_preflight_checks() {
  local missing=0
  local cmd=""
  for cmd in git composer jq; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
      log_error "Missing required command: $cmd"
      missing=1
    fi
  done
  if [ "$missing" -ne 0 ]; then
    exit 1
  fi

  if command -v curl >/dev/null 2>&1; then
    if ! curl -sf --max-time 10 https://packages.drupal.org/8/packages.json >/dev/null; then
      log_error "Cannot reach packages.drupal.org (network/repository unavailable)."
      exit 1
    fi
  fi
}

run_preflight_checks

# High-level flow:
# 1) Pre-clone issue forks so resolver can see local branch code.
# 2) Resolve a compatible module/CMS plan into logs/ai-manifest.json.
# 3) Clone module repos for local path-repo usage.
# 4) Build/update Composer project, then install Drupal and enable modules.

# Pre-clone issue-fork modules so resolver can use path repositories
# and resolve against the exact branch code under test.
preclone_issue_module() {
  local module_name=$1
  local issue_fork=$2
  local issue_branch=$3
  local repo_dir="$PROJECT_ROOT/repos/$module_name"
  local issue_version=""

  [ -n "$module_name" ] || return 0
  [ -n "$issue_fork" ] || return 0
  [ -n "$issue_branch" ] || return 0

  ensure_module_submodule "$module_name"
  fetch_module_remotes "$repo_dir" "$issue_fork"
  if ! checkout_issue_branch "$repo_dir" "$issue_fork" "$issue_branch"; then
    log_error "Issue branch $issue_branch not found for $module_name on fork $issue_fork."
    exit 1
  fi

  # Make path-repo resolution honour explicitly requested module version.
  # Without this, a branch like 1.x reports 1.x-dev and conflicts with exact
  # constraints such as 1.0.7 during resolver require.
  if [ "$module_name" = "${DP_AI_MODULE:-}" ]; then
    issue_version="$(normalize_version_to_composer "${DP_AI_MODULE_VERSION:-}")"
  elif [ "$module_name" = "${DP_TEST_MODULE:-}" ]; then
    issue_version="$(normalize_version_to_composer "${DP_TEST_MODULE_VERSION:-}")"
  fi

  if [ -n "$issue_version" ] && [ "$issue_version" != "*" ] && [ -f "$repo_dir/composer.json" ] && command -v jq >/dev/null 2>&1; then
    log_info "Applying issue module version for resolver: $module_name -> $issue_version"
    jq --arg version "$issue_version" '.version = $version' \
      "$repo_dir/composer.json" > "$repo_dir/composer.json.tmp" \
      && mv "$repo_dir/composer.json.tmp" "$repo_dir/composer.json"
  fi

  if [ -z "${PRECLONED_ISSUE_MODULES:-}" ]; then
    export PRECLONED_ISSUE_MODULES="$module_name"
  elif ! echo ",$PRECLONED_ISSUE_MODULES," | grep -q ",$module_name,"; then
    export PRECLONED_ISSUE_MODULES="$PRECLONED_ISSUE_MODULES,$module_name"
  fi
}

preclone_issue_module "${DP_AI_MODULE:-}" "${DP_AI_ISSUE_FORK:-}" "${DP_AI_ISSUE_BRANCH:-}"
preclone_issue_module "${DP_TEST_MODULE:-}" "${DP_TEST_MODULE_ISSUE_FORK:-}" "${DP_TEST_MODULE_ISSUE_BRANCH:-}"

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
  if [ -d "$COMPOSER_ROOT/web/sites/default" ]; then
    chmod -R u+w "$COMPOSER_ROOT/web/sites/default" 2>/dev/null || true
  fi
  if [ "$COMPOSER_ROOT" = "$PROJECT_ROOT" ]; then
    echo "Note: COMPOSER_ROOT matches PROJECT_ROOT; skipping removal to avoid deleting scripts."
  else
    time rm -rf "$COMPOSER_ROOT" || echo "Note: Some files couldn't be removed (Mutagen sync active)"
  fi
  echo 'Rebuild mode enabled.'
  echo
fi

# Ensure COMPOSER_ROOT exists and cd into it.
mkdir -p "$COMPOSER_ROOT"
cd "$COMPOSER_ROOT"

# Remove root-owned artifacts (avoid sudo; ignore if not present).
echo
echo "Remove root-owned files."
rm -rf lost+found 2>/dev/null || true

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Composer setup
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# composer_setup.sh creates/refreshes the CMS/Core project from the resolved
# manifest and wires local repos as Composer path repositories.
if [ "${DP_REBUILD:-0}" = "1" ] || [ ! -f composer.json ]; then
  source "$SCRIPT_DIR/composer_setup.sh"
else
  # Skip patch-relisten (composer prl) unless composer.lock has changed since the
  # last run. Patch re-reading is expensive and unnecessary when dependencies are stable.
  if composer show --locked cweagans/composer-patches ^2 &>/dev/null; then
    PRL_MARKER="$LOG_DIR/last-prl-run"
    if [ ! -f "$PRL_MARKER" ] || [ composer.lock -nt "$PRL_MARKER" ]; then
      composer prl
      touch "$PRL_MARKER"
    fi
  fi
fi

# Optionally skip dev dependencies (PHPStan, testing tools, etc.) for faster
# installs when development tooling isn't required. Enable with DP_NO_DEV=1.
COMPOSER_DEV_FLAG=""
if [ "${DP_NO_DEV:-0}" = "1" ]; then
  COMPOSER_DEV_FLAG="--no-dev"
  echo "Skipping dev dependencies (DP_NO_DEV=1)..."
fi

COMPOSER_INSTALL_EXIT=0
COMPOSER_INSTALL_OUT=""
if [ -f composer.lock ]; then
  echo 'Running composer install...'
  set +e
  COMPOSER_INSTALL_OUT=$(time composer -n install --prefer-dist --no-progress $COMPOSER_DEV_FLAG 2>&1)
  COMPOSER_INSTALL_EXIT=$?
  set -e
  echo "$COMPOSER_INSTALL_OUT"
fi

if [ ! -f composer.lock ] || [ "$COMPOSER_INSTALL_EXIT" -ne 0 ]; then
  if [ -f composer.lock ]; then
    echo "Composer install failed (exit=$COMPOSER_INSTALL_EXIT), falling back to composer update..."
  else
    echo 'No composer.lock found, running composer update...'
  fi

  set +e
  COMPOSER_UPDATE_OUT=$(time composer -n update --prefer-dist --no-progress $COMPOSER_DEV_FLAG 2>&1)
  COMPOSER_UPDATE_EXIT=$?
  set -e
  echo "$COMPOSER_UPDATE_OUT"

  if [ "$COMPOSER_UPDATE_EXIT" -ne 0 ]; then
    COMPOSER_UPDATE_CLASSIFICATION=$(classify_composer_failure "$COMPOSER_UPDATE_OUT")
    if [ "$COMPOSER_UPDATE_EXIT" -eq 2 ] && [ "$COMPOSER_UPDATE_CLASSIFICATION" = "dependency_conflict" ]; then
      echo "Composer update failed (exit=$COMPOSER_UPDATE_EXIT, classification=$COMPOSER_UPDATE_CLASSIFICATION). Stopping."
      exit 1
    fi

    echo "Composer update failed (exit=$COMPOSER_UPDATE_EXIT, classification=$COMPOSER_UPDATE_CLASSIFICATION). Stopping."
    exit 1
  fi
fi

if [ -n "${DP_ALIAS_MODULES:-}" ]; then
  echo
  echo "Resetting temporary branch aliases..."
  IFS=',' read -ra ALIAS_MODULES <<< "$DP_ALIAS_MODULES"
  for module in "${ALIAS_MODULES[@]}"; do
    repo="$PROJECT_ROOT/repos/$module"
    if [ -d "$repo/.git" ]; then
      git -C "$repo" checkout -- composer.json 2>/dev/null || true
    fi
  done
fi

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
if [ -n "${COMPATIBLE_MODULES:-}" ] && [ -d "$PROJECT_ROOT/repos" ]; then
  echo
  echo "Git status for enabled modules:"
  modules_list="$COMPATIBLE_MODULES"
  for extra_module in "${DP_AI_MODULE:-}" "${DP_TEST_MODULE:-}"; do
    if [ -n "$extra_module" ] && ! echo ",$modules_list," | grep -q ",${extra_module},"; then
      modules_list="${modules_list},${extra_module}"
    fi
  done
  IFS=',' read -ra MODULES <<< "$modules_list"
  for module in "${MODULES[@]}"; do
    repo="$PROJECT_ROOT/repos/$module"
    if [ ! -d "$repo" ]; then
      continue
    fi
    if git -C "$repo" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      top_level="$(git -C "$repo" rev-parse --show-toplevel 2>/dev/null || true)"
      if [ "$top_level" = "$repo" ]; then
        echo
        echo "[$module]"
        version_ref=$(git -C "$repo" describe --tags --always --dirty 2>/dev/null || git -C "$repo" rev-parse --short HEAD)
        echo "Git ref: $version_ref"
        git -C "$repo" status -sb
      fi
    else
      echo
      echo "[WARN] $module is enabled but not a git repository at: $repo"
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
