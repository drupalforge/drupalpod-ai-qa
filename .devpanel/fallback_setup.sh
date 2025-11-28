#!/usr/bin/env bash
set -eu -o pipefail

# Set defaults for DrupalPod AI QA
export DP_STARTER_TEMPLATE=${DP_STARTER_TEMPLATE:='cms'}

# Set default version based on starter template
if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
  # CMS versions: 1.0.0, 1.1.x, 2.0.0, etc.
  export DP_VERSION=${DP_VERSION:='1.x'}
else
  # Core versions: 11.2.8, 11.x, 10.1.5, etc.
  export DP_VERSION=${DP_VERSION:='11.2.8'}
fi

# Optional: Enable extra modules (disabled for Drupal 11)
export DP_EXTRA_DEVEL=1
export DP_EXTRA_ADMIN_TOOLBAR=1

# Default install profile (can be overridden)
if [ -z "${DP_INSTALL_PROFILE:-}" ]; then
  if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
    # For CMS, empty string means auto-detect drupal_cms_installer
    export DP_INSTALL_PROFILE=''
  else
    # For core, use standard profile by default
    export DP_INSTALL_PROFILE='standard'
  fi
fi

# Validate version format matches template choice
if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
  # CMS versions should be like 1.x, 2.x, 1.0.0, 2.0.0, not like 9.x or higher (which are core)
  if [[ "$DP_VERSION" =~ ^[0-9]+ ]]; then
    major_version=$(echo "$DP_VERSION" | cut -d. -f1)
    if [ "$major_version" -ge 9 ]; then
      echo "ERROR: Version '$DP_VERSION' looks like a Drupal core version, but you selected CMS template."
      echo "CMS versions should be like: 1.0.0, 1.1.x, 1.x-dev, 2.0.0, 2.x, etc."
      exit 1
    fi
  fi
else
  # Core versions should be like 9.x, 10.x, 11.2.8, not like 1.0.0 or 2.0.0
  if [[ "$DP_VERSION" =~ ^[1-2]\. ]]; then
    echo "ERROR: Version '$DP_VERSION' looks like a CMS version, but you selected core template."
    echo "Core versions should be like: 11.2.8, 11.x, 10.1.5, 10.x, 9.x"
    exit 1
  fi
fi

# Set install profile based on starter template (only if not already set)
# For CMS, don't specify a profile - let Drupal auto-detect the distribution
if [ -z "${DP_INSTALL_PROFILE+x}" ]; then
  if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
    export DP_INSTALL_PROFILE=''
  else
    export DP_INSTALL_PROFILE='standard'
  fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI MODULE CONFIGURATION (always use git for AI modules)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Auto-detect compatible AI module version based on CMS/Core version
if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
    case "$DP_VERSION" in
        2.0.x|2.x|2.0.*)
            # CMS 2.x requires AI ^1.2
            DEFAULT_AI_VERSION="1.2.x"
            echo "Detected CMS 2.x → Using AI modules 1.2.x"
            ;;
        1.x|1.0.x|1.*.*)
            # CMS 1.x requires AI ^1.0
            DEFAULT_AI_VERSION="1.0.x"
            echo "Detected CMS 1.x → Using AI modules 1.0.x"
            ;;
        *)
            echo "⚠️  WARNING: Unknown CMS version '$DP_VERSION', defaulting to AI 1.2.x"
            DEFAULT_AI_VERSION="1.2.x"
            ;;
    esac
else
    # Drupal Core
    case "$DP_VERSION" in
        11.*|11.x)
            # Drupal 11.x works with AI ^1.2
            DEFAULT_AI_VERSION="1.2.x"
            echo "Detected Drupal Core 11.x → Using AI modules 1.2.x"
            ;;
        10.*|10.x)
            # Drupal 10.x works with AI ^1.0
            DEFAULT_AI_VERSION="1.0.x"
            echo "Detected Drupal Core 10.x → Using AI modules 1.0.x"
            ;;
        *)
            echo "⚠️  WARNING: Unknown Core version '$DP_VERSION', defaulting to AI 1.2.x"
            DEFAULT_AI_VERSION="1.2.x"
            ;;
    esac
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# AI Module Configuration (Dependency-Driven Architecture)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# AI base module (ALWAYS cloned from git)
export DP_AI_MODULE=${DP_AI_MODULE:-'ai'}

# Track if user explicitly set AI version (for validation when testing modules)
if [ -z "${DP_AI_MODULE_VERSION:-}" ]; then
    # User didn't set it - use default and mark as auto-detected
    export DP_AI_MODULE_VERSION="$DEFAULT_AI_VERSION"
    export DP_AI_MODULE_VERSION_EXPLICIT="no"
else
    # User explicitly set it - validate compatibility when testing modules
    export DP_AI_MODULE_VERSION_EXPLICIT="yes"
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
