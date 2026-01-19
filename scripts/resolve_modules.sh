#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Resolve AI Module Versions via Composer.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This script builds a temporary Drupal project and asks Composer to
# resolve concrete versions for AI-related modules. It writes a plan
# file (logs/ai-manifest.json) that clone_modules.sh consumes.

# Load common utilities (skip if already loaded by parent script).
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/lib/common.sh"
    init_common
fi
require_jq

# Export manifest file location for other scripts.
export DP_MODULE_MANIFEST="$MANIFEST_FILE"

# Normalise user-friendly versions to Composer constraints.
# Direction: user input -> Composer constraint.
# Examples:
#  - "" -> "*"
#  - "1.x" -> "1.x-dev"
#  - "1.2" -> "1.2".
normalize_module_version() {
    local version=${1:-}

    if [ -z "$version" ]; then
        echo "*"
        return
    fi

    if [[ "$version" == *.x ]]; then
        echo "${version}-dev"
        return
    fi

    echo "$version"
}

# Convert bash args into a JSON array, to create Composer-friendly
# lists of packages.
# Example:
#  - "a" "b" => ["a","b"]
json_array_from_list() {
    local items=("$@")

    if [ "${#items[@]}" -eq 0 ]; then
        echo "[]"
        return
    fi

    printf '%s\n' "${items[@]}" | jq -R . | jq -s .
}

# Simple dedupe helper for package lists.
# Check if a package name exists in a list,
# Returns 0 if found, 1 if not.
contains_package() {
    local name=$1
    shift
    local list=("$@")

    for existing in "${list[@]}"; do
        if [ "$existing" = "$name" ]; then
            return 0
        fi
    done

    return 1
}

# Add a required module (if not already present).
add_required_module() {
    local name=$1
    local constraint=$2

    if contains_package "$name" "${REQUIRED_PACKAGES[@]}"; then
        return
    fi

    REQUIRED_PACKAGES+=("$name")
    REQUIRED_CONSTRAINTS+=("$constraint")
}

# Add an optional module (if not already present).
add_optional_module() {
    local name=$1
    local constraint=$2

    if contains_package "$name" "${REQUIRED_PACKAGES[@]}"; then
        return
    fi

    if contains_package "$name" "${OPTIONAL_PACKAGES[@]}"; then
        return
    fi

    OPTIONAL_PACKAGES+=("$name")
    OPTIONAL_CONSTRAINTS+=("$constraint")
}

# Emit a manifest file with only requested packages and their
# resolved versions. This plan is later consumed by
# clone_modules.sh. It is written to $MANIFEST_FILE.
write_manifest_from_lock() {
    local lock_path=$1
    local requested_json=$2
    local skipped_json=$3
    local out_path=$4
    local starter_template=$5
    local dp_version=$6

    jq --argjson requested "$requested_json" \
        --argjson skipped "$skipped_json" \
        --arg starter "$starter_template" \
        --arg dp_version "$dp_version" \
        '{
            generated_at: (now | todate),
            starter_template: $starter,
            dp_version: $dp_version,
            requested_packages: $requested,
            skipped_packages: $skipped,
            packages: [
                .packages[]
                | select(.name as $n | ($requested | index($n)))
                | {name, version}
            ]
        }' "$lock_path" > "$out_path"
}

# Decide which base project to resolve against (CMS vs core).
STARTER_TEMPLATE="${DP_STARTER_TEMPLATE:-cms}"
DP_VERSION="${DP_VERSION:-}"

# Determine Composer project and version constraint.
source "$SCRIPT_DIR/lib/project_selector.sh"
resolve_project_selection

# Track required vs optional (optional are allowed to be skipped).
REQUIRED_PACKAGES=()
REQUIRED_CONSTRAINTS=()
OPTIONAL_PACKAGES=()
OPTIONAL_CONSTRAINTS=()
SKIPPED_PACKAGES=()

# If a test module is provided, include it first so it has priority in resolution.
# Composer will still resolve the base AI module, but the test module drives compatibility.
if [ -n "${DP_TEST_MODULE:-}" ]; then
    test_pkg="drupal/${DP_TEST_MODULE}"
    test_constraint="$(normalize_module_version "${DP_TEST_MODULE_VERSION:-}")"
    add_required_module "$test_pkg" "$test_constraint"
fi

# Always include the base AI module in the Composer resolution plan.
# If DP_AI_MODULE_VERSION is blank, we allow any compatible version.
# If it is a branch like "1.x", it is normalized to "1.x-dev".
base_pkg="drupal/${DP_AI_MODULE}"
base_constraint="$(normalize_module_version "${DP_AI_MODULE_VERSION:-}")"
add_required_module "$base_pkg" "$base_constraint"

# Collect optional modules from DP_AI_MODULES. These are "try if possible":
# we attempt to add them after the base AI version is resolved and skip any
# that conflict, recording them in the final plan.
if [ -n "${DP_AI_MODULES:-}" ]; then
    IFS=',' read -ra MODULES <<< "$DP_AI_MODULES"
    for module in "${MODULES[@]}"; do
        module=$(echo "$module" | xargs)
        [ -n "$module" ] || continue
        if [ "$module" = "${DP_AI_MODULE:-ai}" ] || [ "$module" = "${DP_TEST_MODULE:-}" ]; then
            continue
        fi
        add_optional_module "drupal/$module" "*"
    done
fi

# Build a temporary project so Composer can resolve real versions.
TMP_DIR=$(mktemp -d)
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Create the project (with or without version constraint).
if [ -n "$INSTALL_VERSION" ]; then
    composer create-project -n --no-install "$COMPOSER_PROJECT":"$INSTALL_VERSION" "$TMP_DIR"
else
    composer create-project -n --no-install "$COMPOSER_PROJECT" "$TMP_DIR"
fi

cd "$TMP_DIR"

# Keep the resolver permissive so we can test dev branches and lenient overrides.
composer config --no-plugins allow-plugins.mglaman/composer-drupal-lenient true
composer config minimum-stability dev

# Determine which packages need lenient mode to bypass CMS/core constraints.
LENIENT_PACKAGES=()

# If AI version explicitly set, bypass CMS/core constraints.
if [ -n "${DP_AI_MODULE_VERSION:-}" ]; then
    LENIENT_PACKAGES+=("drupal/${DP_AI_MODULE}")
fi

# If AI version is explicit, allow the test module to bypass strict constraints.
if [ -n "${DP_TEST_MODULE:-}" ] && [ -n "${DP_AI_MODULE_VERSION:-}" ]; then
    LENIENT_PACKAGES+=("drupal/${DP_TEST_MODULE}")
fi

# Enable lenient mode only if needed. This allows Composer to bypass
# strict core/CMS constraints for explicit tests.
if [ "${#LENIENT_PACKAGES[@]}" -gt 0 ]; then
    echo "Enabling lenient mode for: ${LENIENT_PACKAGES[*]}"
    allow_list_json=$(json_array_from_list "${LENIENT_PACKAGES[@]}")
    composer require --prefer-dist -n --no-update "mglaman/composer-drupal-lenient:^1.0"
    composer config --json extra.drupal-lenient.allowed-list "$allow_list_json"
fi

# Install required packages first (AI base + test module).
for i in "${!REQUIRED_PACKAGES[@]}"; do
    composer require --prefer-dist -n --no-update "${REQUIRED_PACKAGES[$i]}:${REQUIRED_CONSTRAINTS[$i]}"
done

# Run initial update to resolve versions.
composer -n update --no-install --no-progress

# Lock in the resolved AI version if it wasn't explicit.
# This ensures optional modules resolve against a fixed
# base AI version.
if [ -z "${DP_AI_MODULE_VERSION:-}" ]; then
    resolved_ai_version=$(jq -r ".packages[] | select(.name==\"drupal/${DP_AI_MODULE}\") | .version" composer.lock | head -1)
    if [ -n "$resolved_ai_version" ] && [ "$resolved_ai_version" != "null" ]; then
        composer require --prefer-dist -n --no-update "drupal/${DP_AI_MODULE}:${resolved_ai_version}"
        composer -n update --no-install --no-progress
    fi
fi

# At this point, the base AI version is resolved.
if [ -n "${DP_TEST_MODULE:-}" ]; then
    # When testing a module, avoid resolving optionals here.
    # We'll try them during install so they can't block the test module.
    if [ -n "${DP_AI_MODULES:-}" ]; then
        IFS=',' read -ra MODULES <<< "$DP_AI_MODULES"
        for module in "${MODULES[@]}"; do
            module=$(echo "$module" | xargs)
            [ -n "$module" ] || continue
            if [ "$module" = "${DP_AI_MODULE:-ai}" ] || [ "$module" = "${DP_TEST_MODULE}" ]; then
                continue
            fi
            SKIPPED_PACKAGES+=("drupal/$module")
        done
    fi
else
    echo "AI version resolved. Now trying optional modules..."
    # Try to add optional modules one by one (skip if incompatible).
    # Each module gets a trial update; failures are rolled back.
    # @todo Is there a more efficient way to do this with Composer?
    if [ "${#OPTIONAL_PACKAGES[@]}" -gt 0 ]; then
        for i in "${!OPTIONAL_PACKAGES[@]}"; do
            optional_pkg="${OPTIONAL_PACKAGES[$i]}"
            optional_constraint="${OPTIONAL_CONSTRAINTS[$i]}"

            echo "  Trying ${optional_pkg}..."

            # Backup composer files in case this module fails.
            backup_composer

            # Try to add this module.
            composer require --prefer-dist -n --no-update "${optional_pkg}:${optional_constraint}"
            if composer -n update --no-install --no-progress 2>/dev/null; then
                echo "    ✓ ${optional_pkg} is compatible"
                cleanup_composer_backup
                REQUIRED_PACKAGES+=("$optional_pkg")
            else
                echo "    ✗ ${optional_pkg} is incompatible, skipping"
                # Restore previous state.
                restore_composer
                SKIPPED_PACKAGES+=("$optional_pkg")
            fi
        done
    fi
fi

# Write final manifest plan with all requested packages.
ALL_REQUESTED=("${REQUIRED_PACKAGES[@]}")
if [ "${#OPTIONAL_PACKAGES[@]}" -gt 0 ]; then
    ALL_REQUESTED+=("${OPTIONAL_PACKAGES[@]}")
fi

requested_json=$(json_array_from_list "${ALL_REQUESTED[@]}")
skipped_json=$(json_array_from_list "${SKIPPED_PACKAGES[@]}")
write_manifest_from_lock "composer.lock" "$requested_json" "$skipped_json" "$MANIFEST_FILE" "$STARTER_TEMPLATE" "$DP_VERSION"

# Final output.
echo "Resolved AI module plan written to: $MANIFEST_FILE"
