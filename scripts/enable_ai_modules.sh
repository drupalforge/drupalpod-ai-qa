#!/usr/bin/env bash
# Enable all AI modules after Drupal installation.
# This script reads the resolution plan and enables:
# - The base AI module.
# - The test module (if configured).
# - All successfully resolved extra AI modules.

set -euo pipefail

# Load common utilities.
export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/common.sh"
init_common
require_jq

# Check if AI modules are configured.
if [ -z "${DP_AI_MODULE:-}" ]; then
    echo "No AI module configured (DP_AI_MODULE not set), skipping module enablement."
    exit 0
fi

# Check if resolution plan exists.
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "AI resolution plan not found at: $MANIFEST_FILE"
    echo "Skipping module enablement."
    exit 0
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Enabling AI modules"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Extract modules to enable from the resolution plan.
MODULES_TO_ENABLE=()

# Add base AI module.
MODULES_TO_ENABLE+=("${DP_AI_MODULE}")

# Add test module if configured.
if [ -n "${DP_TEST_MODULE:-}" ]; then
    MODULES_TO_ENABLE+=("${DP_TEST_MODULE}")
fi

# Add all successfully resolved modules from the plan.
# Only read packages that match the requested AI modules.
while IFS= read -r package_name; do
    module_name=$(strip_drupal_prefix "$package_name")
    # Skip if it's the base AI module or test module (already added).
    if [ "$module_name" != "${DP_AI_MODULE}" ] && [ "$module_name" != "${DP_TEST_MODULE:-}" ]; then
        MODULES_TO_ENABLE+=("$module_name")
    fi
done < <(jq -r '.packages[].name' "$MANIFEST_FILE" 2>/dev/null || echo "")

# Remove duplicates and sort.
MODULES_TO_ENABLE=($(printf '%s\n' "${MODULES_TO_ENABLE[@]}" | sort -u))

echo "Modules to enable: ${MODULES_TO_ENABLE[*]}"
echo

# Enable all modules at once.
if [ "${#MODULES_TO_ENABLE[@]}" -gt 0 ]; then
    time $DRUSH -n pm:enable "${MODULES_TO_ENABLE[@]}" || {
        echo "Warning: Some modules could not be enabled. This may be expected if they have unmet dependencies."
    }
    echo "✓ AI modules enabled"
else
    echo "No modules to enable."
fi
