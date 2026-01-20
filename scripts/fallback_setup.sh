#!/usr/bin/env bash
set -eu -o pipefail

# Set defaults for DrupalPod AI QA.
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Drupal Starter Template Selection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -z "${DP_STARTER_TEMPLATE:-}" ]; then
  export DP_STARTER_TEMPLATE='cms'
  echo "  → No template specified, using default: cms"
  echo "    Template: $DP_STARTER_TEMPLATE (auto-detected)"
else
  echo "  → Template explicitly set: $DP_STARTER_TEMPLATE"
  echo "    Template: $DP_STARTER_TEMPLATE (explicit)"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Drupal Version Selection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Set default version based on starter template (empty = latest stable).
export DP_VERSION=${DP_VERSION:=''}
if [ -n "$DP_VERSION" ]; then
  echo "  → Version explicitly set: $DP_VERSION"
  echo "    Version: $DP_VERSION (explicit)"
else
  echo "  → No version specified, will use latest stable"
  echo "    Version: latest stable (auto-detected)"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Drupal Install Profile Selection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Default install profile (can be overridden), but we won't document
# this heavily as it's an internal detail for now.
if [ -z "${DP_INSTALL_PROFILE:-}" ]; then
  if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
    # For CMS, we keep the install profile empty to let the installer
    # auto-detect, otherwise it does not work as expected.
    export DP_INSTALL_PROFILE=''
    echo "  → Template is CMS, using auto-detect"
    echo "    Profile: auto-detect (empty for CMS installer)"
  else
    # For core, use standard profile by default. We could personalise
    # this further in the future, but for simplificity we'll keep it
    # as standard, unlike the original DrupalPod.
    export DP_INSTALL_PROFILE='standard'
    echo "  → Template is core, using standard profile"
    echo "    Profile: standard (default for core)"
  fi
else
  echo "  → Profile explicitly set: ${DP_INSTALL_PROFILE}"
  echo "    Profile: ${DP_INSTALL_PROFILE} (explicit)"
fi
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI MODULE CONFIGURATION
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI versions are resolved by Composer in scripts/resolve_modules.sh.
# If DP_TEST_MODULE is set, its constraints influence the AI version.
# If DP_AI_MODULE_VERSION is empty, the resolver picks a compatible version.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# AI base module (ALWAYS cloned from git).
export DP_AI_MODULE=${DP_AI_MODULE:-'ai'}

# Track if user explicitly set AI version.
if [ -z "${DP_AI_MODULE_VERSION:-}" ]; then
    # User didn't set it - leave empty for composer resolution.
    export DP_AI_MODULE_VERSION=""
    echo "  AI version will be auto-detected by composer resolution"
else
    # User explicitly set it.
    echo "  AI version explicitly set to: $DP_AI_MODULE_VERSION"
fi

# AI module PR testing (optional).
export DP_AI_ISSUE_FORK=${DP_AI_ISSUE_FORK:-''}
export DP_AI_ISSUE_BRANCH=${DP_AI_ISSUE_BRANCH:-''}

# Generic test module (optional - any module you're testing).
export DP_TEST_MODULE=${DP_TEST_MODULE:-''}
export DP_TEST_MODULE_VERSION=${DP_TEST_MODULE_VERSION:-''}
export DP_TEST_MODULE_ISSUE_FORK=${DP_TEST_MODULE_ISSUE_FORK:-''}
export DP_TEST_MODULE_ISSUE_BRANCH=${DP_TEST_MODULE_ISSUE_BRANCH:-''}

# Validate optional AI module list against an allowlist to avoid pulling
# unexpected packages from Composer.
ALLOWED_AI_MODULES=()
if [ -n "${PROJECT_ROOT:-}" ] && [ -d "$PROJECT_ROOT/repos" ]; then
    while IFS= read -r -d '' repo_dir; do
        ALLOWED_AI_MODULES+=("$(basename "$repo_dir")")
    done < <(find "$PROJECT_ROOT/repos" -mindepth 1 -maxdepth 1 -type d -print0)
fi

# Fallback allowlist for environments without repos checked out yet.
if [ "${#ALLOWED_AI_MODULES[@]}" -eq 0 ]; then
    ALLOWED_AI_MODULES=(
        ai
        ai_agents
        ai_provider_amazeeio
        ai_provider_anthropic
        ai_provider_litellm
        ai_provider_openai
        ai_search
    )
fi

if [ -n "${DP_AI_MODULES:-}" ]; then
    IFS=',' read -ra REQUESTED_MODULES <<< "$DP_AI_MODULES"
    for module in "${REQUESTED_MODULES[@]}"; do
        module=$(echo "$module" | xargs)
        [ -n "$module" ] || continue
        allowed=false
        for allowed_module in "${ALLOWED_AI_MODULES[@]}"; do
            if [ "$module" = "$allowed_module" ]; then
                allowed=true
                break
            fi
        done
        if [ "$allowed" = "false" ]; then
            echo "ERROR: DP_AI_MODULES includes unsupported module: $module" >&2
            echo "Allowed modules: ${ALLOWED_AI_MODULES[*]}" >&2
            exit 1
        fi
    done
fi

# Function to validate issue version requirements.
require_issue_version() {
    local label="$1"
    local version_var="$2"
    local fork_var="$3"
    local branch_var="$4"
    local version_value="${!version_var:-}"
    local fork_value="${!fork_var:-}"
    local branch_value="${!branch_var:-}"

    if [ -n "$fork_value" ] || [ -n "$branch_value" ]; then
        if [ -z "$version_value" ]; then
            echo "ERROR: $label PR testing requires $version_var when using $fork_var/$branch_var." >&2
            exit 1
        fi
    fi
}

# Validate AI module and test module issue version requirements.
require_issue_version "AI module" "DP_AI_MODULE_VERSION" "DP_AI_ISSUE_FORK" "DP_AI_ISSUE_BRANCH"
require_issue_version "Test module" "DP_TEST_MODULE_VERSION" "DP_TEST_MODULE_ISSUE_FORK" "DP_TEST_MODULE_ISSUE_BRANCH"

# Show final AI module configurations.
echo "  AI Module Configuration:"
echo "   - AI Base: $DP_AI_MODULE @ $DP_AI_MODULE_VERSION"
echo "   - Force Dependencies: ${DP_FORCE_DEPENDENCIES:-0}"
if [ -n "${DP_AI_ISSUE_BRANCH:-}" ]; then
    echo "     └─ Testing PR: $DP_AI_ISSUE_FORK/$DP_AI_ISSUE_BRANCH"
fi
if [ -n "${DP_TEST_MODULE:-}" ]; then
    echo "   - Test Module: $DP_TEST_MODULE"
    if [ -n "${DP_TEST_MODULE_VERSION:-}" ]; then
        echo "     └─ Version: $DP_TEST_MODULE_VERSION"
    fi
    if [ -n "${DP_TEST_MODULE_ISSUE_BRANCH:-}" ]; then
        echo "     └─ Testing PR: $DP_TEST_MODULE_ISSUE_FORK/$DP_TEST_MODULE_ISSUE_BRANCH"
    fi
fi
echo "   - Dependencies: Resolved via Composer manifest"
