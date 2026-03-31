#!/usr/bin/env bash
set -eu -o pipefail

# Load common utilities.
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/lib/bootstrap.sh"

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
  echo "  → No version specified, will auto-detect a compatible version"
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
    # For core, use standard profile by default. We could personalize
    # this further in the future, but for simplicity we'll keep it
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
export DP_FORCE_DEPENDENCIES=${DP_FORCE_DEPENDENCIES:-1}

# Generic test module (optional - any module you're testing).
export DP_TEST_MODULE=${DP_TEST_MODULE:-''}
export DP_TEST_MODULE_VERSION=${DP_TEST_MODULE_VERSION:-''}
export DP_TEST_MODULE_ISSUE_FORK=${DP_TEST_MODULE_ISSUE_FORK:-''}
export DP_TEST_MODULE_ISSUE_BRANCH=${DP_TEST_MODULE_ISSUE_BRANCH:-''}

# Default to amazeeai for CMS if no provider is specified.
# Set DP_AI_PROVIDER=NULL to explicitly disable AI provider setup.
# (Core template is excluded — it does not have the drupal_cms_ai recipe.)
if [ "${DP_AI_PROVIDER:-}" = "NULL" ]; then
    export DP_AI_PROVIDER=''
    echo "  → AI provider disabled (NULL)"
elif [ -z "${DP_AI_PROVIDER:-}" ] && [ "${DP_STARTER_TEMPLATE:-}" = "cms" ]; then
    export DP_AI_PROVIDER='amazeeai'
    echo "  → No AI provider specified, defaulting to: amazeeai"
fi

# If DP_AI_PROVIDER is set, ensure the provider module is included in DP_EXTRA_MODULES
# so it gets pulled from repos and resolved via Composer.
if [ -n "${DP_AI_PROVIDER:-}" ]; then
    resolve_ai_provider "${DP_AI_PROVIDER}"

    # Add provider module to DP_EXTRA_MODULES if not already present
    # Check for module name (handles version constraints like ai_provider_openai@2.0.x)
    if [ -z "${DP_EXTRA_MODULES:-}" ]; then
        export DP_EXTRA_MODULES="${provider_module}"
    elif ! echo ",${DP_EXTRA_MODULES}," | grep -q "[,]${provider_module}[@:,]\\|[,]${provider_module}[,]"; then
        export DP_EXTRA_MODULES="${DP_EXTRA_MODULES},${provider_module}"
    fi
fi

# Hard limit on the number of extra modules that can be requested.
# To change the limit, update MAX_EXTRA_MODULES below — it is referenced
# throughout the validation logic so there is only one place to edit.
readonly MAX_EXTRA_MODULES=15

if [ -n "${DP_EXTRA_MODULES:-}" ]; then
    IFS=',' read -ra REQUESTED_MODULES <<< "$DP_EXTRA_MODULES"
    if [ "${#REQUESTED_MODULES[@]}" -gt "$MAX_EXTRA_MODULES" ]; then
        echo "ERROR: DP_EXTRA_MODULES exceeds the maximum of $MAX_EXTRA_MODULES modules (got ${#REQUESTED_MODULES[@]})." >&2
        exit 1
    fi
fi

# Validate AI module and test module issue version requirements.
validate_issue_version_requirements

# Show final AI module configurations.
echo "  AI Module Configuration:"
echo "   - AI Base: $DP_AI_MODULE @ $DP_AI_MODULE_VERSION"
echo "   - Force Dependencies: ${DP_FORCE_DEPENDENCIES}"
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
