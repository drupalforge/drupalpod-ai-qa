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

# Initialize arrays early for set -u safety in functions.
REQUIRED_PACKAGES=()
REQUIRED_CONSTRAINTS=()
OPTIONAL_PACKAGES=()
OPTIONAL_CONSTRAINTS=()
SKIPPED_PACKAGES=()

# Export manifest file location for other scripts.
export DP_MODULE_MANIFEST="$MANIFEST_FILE"

# Simple dedupe helper for package lists.
# Check if a package name exists in a list,
# Returns 0 if found, 1 if not.
contains_package() {
    local name=$1
    shift
    for existing in "$@"; do
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

    if contains_package "$name" ${REQUIRED_PACKAGES[@]+"${REQUIRED_PACKAGES[@]}"}; then
        return
    fi

    REQUIRED_PACKAGES+=("$name")
    REQUIRED_CONSTRAINTS+=("$constraint")
}

# Add an optional module (if not already present).
add_optional_module() {
    local name=$1
    local constraint=$2

    if contains_package "$name" ${REQUIRED_PACKAGES[@]+"${REQUIRED_PACKAGES[@]}"}; then
        return
    fi

    if contains_package "$name" ${OPTIONAL_PACKAGES[@]+"${OPTIONAL_PACKAGES[@]}"}; then
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

    # Extract resolved versions for CMS and Core from composer.lock
    local cms_version=""
    local core_version=""

    cms_version=$(jq -r '.packages[] | select(.name=="drupal/cms") | .version' "$lock_path" | head -1)
    if [ "$cms_version" = "null" ] || [ -z "$cms_version" ]; then
        cms_version=""
    fi

    # Try both drupal/core-recommended and drupal/core
    core_version=$(jq -r '.packages[] | select(.name=="drupal/core-recommended") | .version' "$lock_path" | head -1)
    if [ "$core_version" = "null" ] || [ -z "$core_version" ]; then
        core_version=$(jq -r '.packages[] | select(.name=="drupal/core") | .version' "$lock_path" | head -1)
        if [ "$core_version" = "null" ] || [ -z "$core_version" ]; then
            core_version=""
        fi
    fi

    jq --argjson requested "$requested_json" \
        --argjson skipped "$skipped_json" \
        --arg starter "$starter_template" \
        --arg dp_version "$dp_version" \
        --arg cms_version "$cms_version" \
        --arg core_version "$core_version" \
        '{
            generated_at: (now | todate),
            starter_template: $starter,
            dp_version: $dp_version,
            resolved_cms_version: $cms_version,
            resolved_core_version: $core_version,
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
FORCE_DEPENDENCIES="${DP_FORCE_DEPENDENCIES:-0}"

# Determine AI resolution base.
# When forcing dependencies with CMS, resolve against core to bypass drupal_cms_ai constraints.
# Otherwise, resolve directly against CMS or Core as appropriate.
RESOLVE_PROJECT=""
RESOLVE_VERSION=""

# If forcing dependencies with CMS, extract core version and resolve against it.
# This bypasses drupal_cms_ai version constraints that would block incompatible AI versions.
if [ "$STARTER_TEMPLATE" = "cms" ] && [ "$FORCE_DEPENDENCIES" = "1" ]; then
    cms_install_version=""

    # If DP_VERSION is set, normalize it for composer.
    if [ -n "${DP_VERSION:-}" ]; then
        cms_install_version="$(normalize_version_to_composer "${DP_VERSION}")"
    fi

    # Create a temporary CMS project to extract core versions.
    cms_tmp_dir=$(mktemp -d)
    if [ -n "$cms_install_version" ]; then
        composer create-project -n --no-install "drupal/cms:$cms_install_version" "$cms_tmp_dir" >/dev/null 2>&1
    else
        composer create-project -n --no-install "drupal/cms" "$cms_tmp_dir" >/dev/null 2>&1
    fi

    # Configure permissive resolution.
    composer -d "$cms_tmp_dir" config minimum-stability dev >/dev/null 2>&1
    composer -d "$cms_tmp_dir" update --no-install --no-progress >/dev/null 2>&1
    RESOLVE_VERSION=$(jq -r '.packages[] | select(.name=="drupal/core-recommended") | .version' "$cms_tmp_dir/composer.lock" | head -1)

    rm -rf "$cms_tmp_dir"

    # Resolve AI modules against core instead of CMS to bypass drupal_cms_ai.
    RESOLVE_PROJECT="drupal/recommended-project"
    log_info "Forcing dependencies: resolving AI against Core $RESOLVE_VERSION (bypassing CMS constraints)"
else
    # Standard resolution: follow CMS/core constraints directly.
    if [ "$STARTER_TEMPLATE" = "cms" ]; then
        RESOLVE_PROJECT="drupal/cms"
        if [ -n "${DP_VERSION:-}" ]; then
            RESOLVE_VERSION="$(normalize_version_to_composer "${DP_VERSION}")"
        fi
    else
        RESOLVE_PROJECT="drupal/recommended-project"
        if [ -n "${DP_VERSION:-}" ]; then
            RESOLVE_VERSION="$(normalize_version_to_composer "${DP_VERSION}")"
        fi
    fi
fi

# If a test module is provided, include it first so it has priority in resolution.
# Composer will still resolve the base AI module, but the test module drives compatibility.
if [ -n "${DP_TEST_MODULE:-}" ]; then
    test_pkg="drupal/${DP_TEST_MODULE}"
    test_constraint="$(normalize_version_to_composer "${DP_TEST_MODULE_VERSION:-}")"
    add_required_module "$test_pkg" "$test_constraint"
fi

# Always include the base AI module in the Composer resolution plan.
# If DP_AI_MODULE_VERSION is blank, we allow any compatible version.
# If it is a branch like "1.x", it is normalized to "1.x-dev".
base_pkg="drupal/${DP_AI_MODULE}"
base_constraint="$(normalize_version_to_composer "${DP_AI_MODULE_VERSION:-}")"
add_required_module "$base_pkg" "$base_constraint"

# Collect optional modules from DP_AI_MODULES. These are "try if possible":
# we attempt to add them after the base AI version is resolved and skip any
# that conflict, recording them in the final manifest.
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

# Auto-detect compatible version when DP_VERSION is empty
# This lets Composer find the best CMS/Core version based on all requirements
AUTO_DETECT_VERSION=0
if [ -z "$RESOLVE_VERSION" ]; then
    AUTO_DETECT_VERSION=1
    if [ -n "${DP_TEST_MODULE:-}" ]; then
        log_info "Auto-detecting compatible $RESOLVE_PROJECT version based on ${DP_TEST_MODULE} requirements"
    else
        log_info "Auto-detecting compatible $RESOLVE_PROJECT version based on ${DP_AI_MODULE} requirements"
    fi
fi

# Create the project (with or without version constraint).
create_project_with_version_fallback() {
    local project=$1
    local version=$2
    local target_dir=$3

    if composer create-project -n --no-install "${project}:${version}" "$target_dir"; then
        return 0
    fi

    # Some templates resolve branch aliases differently for create-project.
    if [[ "$version" == *.x-dev ]]; then
        local fallback_version="${version%-dev}"
        log_warn "create-project failed for ${project}:${version}; retrying with ${project}:${fallback_version}"
        composer create-project -n --no-install "${project}:${fallback_version}" "$target_dir"
        return 0
    fi

    return 1
}

if [ "$AUTO_DETECT_VERSION" = "1" ]; then
    # Don't use create-project - it locks to latest. Instead, init empty project.
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"
    composer init --no-interaction --name="drupalpod/temp-resolver" --type="project"
    composer config minimum-stability dev
    # Add CMS/Core WITHOUT version constraint so Composer can choose compatible version
    composer require --no-update "$RESOLVE_PROJECT"
else
    # Normal flow: pin to specific version or use latest
    if [ -n "$RESOLVE_VERSION" ]; then
        create_project_with_version_fallback "$RESOLVE_PROJECT" "$RESOLVE_VERSION" "$TMP_DIR"
    else
        composer create-project -n --no-install "$RESOLVE_PROJECT" "$TMP_DIR"
    fi
    cd "$TMP_DIR"
    composer config minimum-stability dev
fi

# Enable lenient mode for initial resolution when forcing incompatible versions.
# This allows required packages (AI base + test module) to resolve even if incompatible.
# Optional modules are tested later with --no-plugins to ensure genuine compatibility.
if [ "$FORCE_DEPENDENCIES" = "1" ]; then
    LENIENT_PACKAGES=("drupal/ai" "drupal/ai_*")

    # If there's a test module, add it explicitly to lenient list.
    if [ -n "${DP_TEST_MODULE:-}" ]; then
        LENIENT_PACKAGES+=("drupal/${DP_TEST_MODULE}")
    fi

    export DP_LENIENT_PACKAGES="$(IFS=,; echo "${LENIENT_PACKAGES[*]}")"
    log_info "Enabling lenient mode for required package resolution: ${LENIENT_PACKAGES[*]}"

    # Enable local AI lenient plugin in resolver context so module->AI
    # constraints (e.g. ai_context -> drupal/ai ^1.3) can be relaxed too.
    plugin_path="$PROJECT_ROOT/src/ai-lenient-plugin"
    if [ -d "$plugin_path" ]; then
        composer config --no-plugins allow-plugins.drupalpod/ai-lenient-plugin true
        composer config --no-plugins repositories.ai-lenient-plugin \
            "{\"type\": \"path\", \"url\": \"$plugin_path\", \"options\": {\"symlink\": true}}"
        composer require --prefer-dist -n --no-update "drupalpod/ai-lenient-plugin:*@dev"
    fi

    # Also enable mglaman/composer-drupal-lenient for broad ecosystem relaxation.
    configure_lenient_mode "${LENIENT_PACKAGES[@]}"

    # Warm up plugin installation so pre-pool rewrites are active during solve.
    # Plugins must be actually installed (not just locked) to be activated.
    # Install just the plugins first, then they'll be active for subsequent updates.
    composer -n update --no-progress \
        mglaman/composer-drupal-lenient \
        drupalpod/ai-lenient-plugin

    # Verify plugins are installed.
    if [ ! -d "vendor/drupalpod/ai-lenient-plugin" ]; then
        log_warn "AI lenient plugin not installed in vendor/"
    fi
fi

# Install required packages first (AI base + test module).
for i in "${!REQUIRED_PACKAGES[@]}"; do
    composer require --prefer-dist -n --no-update "${REQUIRED_PACKAGES[$i]}:${REQUIRED_CONSTRAINTS[$i]}"
done

# Run initial update to resolve versions.
# Use --with-all-dependencies to ensure lenient plugins process all packages.
if [ "$FORCE_DEPENDENCIES" = "1" ]; then
    composer -n update --no-install --no-progress --with-all-dependencies
else
    composer -n update --no-install --no-progress
fi

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

    # Test optional modules for genuine compatibility without lenient mode.
    # Use --no-plugins flag to disable lenient during testing for maximum performance.
    if [ "${#OPTIONAL_PACKAGES[@]}" -gt 0 ]; then
        for i in "${!OPTIONAL_PACKAGES[@]}"; do
            optional_pkg="${OPTIONAL_PACKAGES[$i]}"
            optional_constraint="${OPTIONAL_CONSTRAINTS[$i]}"

            echo "  Trying ${optional_pkg}..."

            # Backup current state.
            cp composer.json composer.json.bak
            cp composer.lock composer.lock.bak 2>/dev/null || true

            # Test compatibility with --no-plugins to disable lenient mode.
            # This is the fastest approach: no temp dirs, no file operations.
            composer require --prefer-dist -n --no-update "${optional_pkg}:${optional_constraint}"
            if composer -n update --no-plugins --no-install --no-progress 2>/dev/null; then
                echo "    ✓ ${optional_pkg} is compatible."
                REQUIRED_PACKAGES+=("$optional_pkg")
                # Keep the changes - remove backups.
                rm -f composer.json.bak composer.lock.bak
            else
                echo "    ✗ ${optional_pkg} is incompatible, skipping."
                # Restore previous state.
                mv composer.json.bak composer.json
                mv composer.lock.bak composer.lock 2>/dev/null || true
                SKIPPED_PACKAGES+=("$optional_pkg")
            fi
        done

        # Final update in main environment with all compatible optionals.
        composer -n update --no-install --no-progress
    fi
fi

# Write final manifest plan with all requested packages.
ALL_REQUESTED=("${REQUIRED_PACKAGES[@]}")
if [ "${#OPTIONAL_PACKAGES[@]}" -gt 0 ]; then
    ALL_REQUESTED+=("${OPTIONAL_PACKAGES[@]}")
fi

requested_json=$(build_json_array "${ALL_REQUESTED[@]}")
if [ "${#SKIPPED_PACKAGES[@]}" -gt 0 ]; then
    skipped_json=$(build_json_array "${SKIPPED_PACKAGES[@]}")
else
    skipped_json="[]"
fi
write_manifest_from_lock "composer.lock" "$requested_json" "$skipped_json" "$MANIFEST_FILE" "$STARTER_TEMPLATE" "$DP_VERSION"

# Final output.
log_info "Resolved AI module plan written to: $MANIFEST_FILE"
