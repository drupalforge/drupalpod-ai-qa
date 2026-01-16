#!/usr/bin/env bash
set -eu -o pipefail

# Set defaults for DrupalPod AI QA (DDEV and Docker builds)
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Drupal Starter Template Selection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -z "${DP_STARTER_TEMPLATE:-}" ]; then
  export DP_STARTER_TEMPLATE='cms'
  echo "  → No template specified, using default: cms"
  echo "  📦 Template: $DP_STARTER_TEMPLATE (auto-detected)"
else
  echo "  → Template explicitly set: $DP_STARTER_TEMPLATE"
  echo "  📦 Template: $DP_STARTER_TEMPLATE (explicit)"
fi
echo ""

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Drupal Version Selection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Set default version based on starter template (empty = latest stable)
export DP_VERSION=${DP_VERSION:=''}
if [ -n "$DP_VERSION" ]; then
  echo "  → Version explicitly set: $DP_VERSION"
  echo "  📦 Version: $DP_VERSION (explicit)"
else
  echo "  → No version specified, using latest stable"
  echo "  📦 Version: latest stable (auto-detected)"
fi
echo ""

# Optional: Enable extra modules (disabled for Drupal 11)
export DP_EXTRA_DEVEL=1
export DP_EXTRA_ADMIN_TOOLBAR=1

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Drupal Install Profile Selection"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
# Default install profile (can be overridden)
if [ -z "${DP_INSTALL_PROFILE:-}" ]; then
  if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
    # For CMS, empty string means auto-detect drupal_cms_installer
    export DP_INSTALL_PROFILE=''
    echo "  → Template is CMS, using auto-detect"
    echo "  📦 Profile: auto-detect (empty for CMS installer)"
  else
    # For core, use standard profile by default
    export DP_INSTALL_PROFILE='standard'
    echo "  → Template is core, using standard profile"
    echo "  📦 Profile: standard (default for core)"
  fi
else
  echo "  → Profile explicitly set: ${DP_INSTALL_PROFILE}"
  echo "  📦 Profile: ${DP_INSTALL_PROFILE} (explicit)"
fi
echo ""

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI MODULE CONFIGURATION (Dependency-Driven Architecture)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI version is dynamically determined from:
# 1. Test module's composer.json (if DP_TEST_MODULE set)
# 2. Latest dev branch (if not set)
# No hardcoded version mappings - let dependencies drive the version!
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# AI base module (ALWAYS cloned from git)
export DP_AI_MODULE=${DP_AI_MODULE:-'ai'}

# Track if user explicitly set AI version (for validation when testing modules)
if [ -z "${DP_AI_MODULE_VERSION:-}" ]; then
    # User didn't set it - leave empty for auto-detection from test module
    # If no test module, clone_ai_modules.sh will use latest dev branch
    export DP_AI_MODULE_VERSION=""
    export DP_AI_MODULE_VERSION_EXPLICIT="no"
    echo "📦 AI version will be auto-detected from test module dependencies"
else
    # User explicitly set it - validate compatibility when testing modules
    export DP_AI_MODULE_VERSION_EXPLICIT="yes"
    echo "📦 AI version explicitly set to: $DP_AI_MODULE_VERSION"
fi

export DP_AI_ISSUE_FORK=${DP_AI_ISSUE_FORK:-''}
export DP_AI_ISSUE_BRANCH=${DP_AI_ISSUE_BRANCH:-''}

# Generic test module (optional - any module you're testing)
export DP_TEST_MODULE=${DP_TEST_MODULE:-''}              # e.g., 'ai_search', 'ai_provider_litellm', 'ai_agents'
export DP_TEST_MODULE_VERSION=${DP_TEST_MODULE_VERSION:-''}  # Optional: specific version/branch
export DP_TEST_MODULE_ISSUE_FORK=${DP_TEST_MODULE_ISSUE_FORK:-''}
export DP_TEST_MODULE_ISSUE_BRANCH=${DP_TEST_MODULE_ISSUE_BRANCH:-''}

# Show final AI module configuration
echo "📦 AI Module Configuration:"
echo "   - AI Base: $DP_AI_MODULE @ $DP_AI_MODULE_VERSION"
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
echo "   - Dependencies: Auto-resolved from composer.json"
