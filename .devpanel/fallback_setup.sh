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

# Set install profile based on starter template
# For CMS, don't specify a profile - let Drupal auto-detect the distribution
if [ "$DP_STARTER_TEMPLATE" = "cms" ]; then
  export DP_INSTALL_PROFILE=''
else
  export DP_INSTALL_PROFILE='standard'
fi
