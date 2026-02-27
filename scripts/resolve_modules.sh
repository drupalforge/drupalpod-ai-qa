#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Resolve AI Module Versions via Composer.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# This script builds a temporary Drupal project and asks Composer to
# resolve concrete versions for AI-related modules. It writes a plan
# file (logs/ai-manifest.json) that clone_modules.sh consumes.
# Downstream scripts should follow this manifest rather than re-solving.

# Load common utilities.
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
fi
source "$SCRIPT_DIR/lib/bootstrap.sh"
source "$SCRIPT_DIR/lib/resolve_mode.sh"
source "$SCRIPT_DIR/lib/resolve_modes.sh"
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
    local resolved_project_package=$7
    local resolved_project_version_hint=$8
    local mode=${9:-0}
    local compatibility=${10:-"clean"}
    local forced_reason=${11:-""}
    local forced_reason_log=${12:-""}
    local ai_package=${13:-""}
    local ai_issue_branch=${14:-""}
    local test_package=${15:-""}
    local test_issue_branch=${16:-""}
    local out_dir=""

    out_dir="$(dirname "$out_path")"
    mkdir -p "$out_dir"

    # Extract CMS/Core versions for traceability and deterministic setup.
    # composer_setup.sh uses these when DP_VERSION is not explicitly set.
    local cms_version=""
    local core_version=""

    cms_version=$(jq -r '.packages[] | select(.name=="drupal/cms") | .version' "$lock_path" | head -1)
    if [ "$cms_version" = "null" ] || [ -z "$cms_version" ]; then
        if [ "$resolved_project_package" = "drupal/cms" ] && [ -n "$resolved_project_version_hint" ]; then
            cms_version="$resolved_project_version_hint"
        else
            cms_version=""
        fi
    fi

    # Try both drupal/core-recommended and drupal/core
    core_version=$(jq -r '.packages[] | select(.name=="drupal/core-recommended") | .version' "$lock_path" | head -1)
    if [ "$core_version" = "null" ] || [ -z "$core_version" ]; then
        core_version=$(jq -r '.packages[] | select(.name=="drupal/core") | .version' "$lock_path" | head -1)
        if [ "$core_version" = "null" ] || [ -z "$core_version" ]; then
            if [ "$resolved_project_package" = "drupal/core-recommended" ] && [ -n "$resolved_project_version_hint" ]; then
                core_version="$resolved_project_version_hint"
            else
                core_version=""
            fi
        fi
    fi

    jq --argjson requested "$requested_json" \
        --argjson skipped "$skipped_json" \
        --arg starter "$starter_template" \
        --arg dp_version "$dp_version" \
        --arg cms_version "$cms_version" \
        --arg core_version "$core_version" \
        --arg resolved_project_package "$resolved_project_package" \
        --arg resolved_project_version_hint "$resolved_project_version_hint" \
        --arg mode "$mode" \
        --arg compatibility "$compatibility" \
        --arg forced_reason "$forced_reason" \
        --arg forced_reason_log "$forced_reason_log" \
        --arg ai_package "$ai_package" \
        --arg ai_issue_branch "$ai_issue_branch" \
        --arg test_package "$test_package" \
        --arg test_issue_branch "$test_issue_branch" \
        '{
            generated_at: (now | todate),
            starter_template: $starter,
            dp_version: $dp_version,
            resolution_mode: ($mode | tonumber),
            mode: ($mode | tonumber),
            compatibility: $compatibility,
            forced_reason: $forced_reason,
            forced_reason_log: $forced_reason_log,
            resolved_project_package: $resolved_project_package,
            resolved_project_version: (
                (
                    first(
                        (
                            .packages + (.["packages-dev"] // [])
                        )[]
                        | select(.name == $resolved_project_package)
                        | .version
                    ) // ""
                ) as $lock_version
                | if ($lock_version != "") then
                    $lock_version
                  elif ($resolved_project_version_hint != "") then
                    $resolved_project_version_hint
                  else
                    ""
                  end
            ),
            resolved_cms_version: $cms_version,
            resolved_core_version: $core_version,
            requested_packages: $requested,
            skipped_packages: $skipped,
            packages: [
                .packages[]
                | select(.name as $n | ($requested | index($n)))
                | {
                    name,
                    version: (
                        if (.name == $ai_package and $ai_issue_branch != "") then
                            ("dev-" + $ai_issue_branch)
                        elif (.name == $test_package and $test_issue_branch != "") then
                            ("dev-" + $test_issue_branch)
                        else
                            .version
                        end
                    )
                }
            ]
        }' "$lock_path" > "$out_path"
}

write_error_manifest() {
    local out_path=$1
    local mode=$2
    local compatibility=$3
    local forced_reason=$4
    local forced_reason_log=$5
    local starter_template=$6
    local dp_version=$7
    local out_dir=""

    out_dir="$(dirname "$out_path")"
    mkdir -p "$out_dir"

    jq -n \
        --arg starter "$starter_template" \
        --arg dp_version "$dp_version" \
        --arg mode "$mode" \
        --arg compatibility "$compatibility" \
        --arg forced_reason "$forced_reason" \
        --arg forced_reason_log "$forced_reason_log" \
        '{
            generated_at: (now | todate),
            starter_template: $starter,
            dp_version: $dp_version,
            mode: ($mode | tonumber),
            compatibility: $compatibility,
            forced_reason: $forced_reason,
            forced_reason_log: $forced_reason_log,
            resolved_project_package: "",
            resolved_project_version: "",
            resolved_cms_version: "",
            resolved_core_version: "",
            requested_packages: [],
            skipped_packages: [],
            packages: []
        }' > "$out_path"
}

# Decide which base project to resolve against (CMS vs core).
STARTER_TEMPLATE="${DP_STARTER_TEMPLATE:-cms}"
DP_VERSION="${DP_VERSION:-}"
FORCE_DEPENDENCIES="${DP_FORCE_DEPENDENCIES}"
NORMALIZED_DP_VERSION="$(normalize_version_to_composer "${DP_VERSION:-}")"
NORMALIZED_AI_VERSION="$(normalize_version_to_composer "${DP_AI_MODULE_VERSION:-}")"
NORMALIZED_TEST_VERSION="$(normalize_version_to_composer "${DP_TEST_MODULE_VERSION:-}")"
MODE=0
COMPATIBILITY="clean"
FORCED_REASON=""
FORCED_REASON_LOG=""
PRIMARY_RESOLVED=0
COMPOSER_OUT=""
COMPOSER_EXIT=0
CLASSIFICATION=""

MODE=$(select_mode "$NORMALIZED_AI_VERSION" "$NORMALIZED_DP_VERSION" "$NORMALIZED_TEST_VERSION" "${DP_AI_ISSUE_BRANCH:-}" "${DP_TEST_MODULE_ISSUE_BRANCH:-}")
log_info "Resolution mode: ${MODE}"
unset DP_LENIENT_PACKAGES || true
# Lenient scope must be explicit per run (Mode 4), never inherited.

# Determine AI resolution base.
# Always resolve against the selected starter template:
# - cms  -> drupal/cms
# - core -> drupal/recommended-project
RESOLVE_PROJECT=""
RESOLVE_VERSION=""
if [ "$STARTER_TEMPLATE" = "cms" ]; then
    RESOLVE_PROJECT="drupal/cms"
    if [ "$NORMALIZED_DP_VERSION" != "*" ]; then
        RESOLVE_VERSION="$NORMALIZED_DP_VERSION"
    fi
else
    RESOLVE_PROJECT="drupal/recommended-project"
    if [ "$NORMALIZED_DP_VERSION" != "*" ]; then
        RESOLVE_VERSION="$NORMALIZED_DP_VERSION"
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

# In MODE 3 (auto-detection), add CMS/Core to resolution so Composer picks latest compatible version.
# This ensures the manifest contains the resolved version for composer_setup.sh to use.
if [ "$MODE" = "$MODE_AUTO" ] && [ -z "${DP_VERSION:-}" ]; then
    if [ "$STARTER_TEMPLATE" = "cms" ]; then
        log_info "Adding drupal/cms to resolution for auto-detection"
        add_required_module "drupal/cms" "*"
    else
        log_info "Adding drupal/core-recommended to resolution for auto-detection"
        add_required_module "drupal/core-recommended" "*"
    fi
fi

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
[ -n "$TMP_DIR" ] || { log_error "Failed to create temp directory"; exit 1; }
cleanup() {
    rm -rf "$TMP_DIR"
}
trap cleanup EXIT

# Create the project (with or without version constraint).
create_project_with_version_fallback() {
    local project=$1
    local version=$2
    local target_dir=$3
    local no_install=${4:-0}
    local create_flags=(-n)

    if [ "$no_install" = "1" ]; then
        create_flags+=(--no-install)
    fi

    if composer create-project --no-plugins "${create_flags[@]}" "${project}:${version}" "$target_dir"; then
        return 0
    fi

    # Some templates resolve branch aliases differently for create-project.
    if [[ "$version" == *.x-dev ]]; then
        local fallback_version="${version%-dev}"
        log_warn "create-project failed for ${project}:${version}; retrying with ${project}:${fallback_version}"
        # Clean up partially-populated directory before retry
        rm -rf "$target_dir"
        composer create-project --no-plugins "${create_flags[@]}" "${project}:${fallback_version}" "$target_dir"
        return 0
    fi

    return 1
}

configure_resolver_allow_plugins() {
    # Keep resolver non-interactive by explicitly declaring trusted/blocked plugins.
    composer config --no-plugins allow-plugins.composer/installers true
    composer config --no-plugins allow-plugins.drupal/core-composer-scaffold true
    composer config --no-plugins allow-plugins.drupal/core-recipe-unpack true
    composer config --no-plugins allow-plugins.drupal/core-project-message true
    composer config --no-plugins allow-plugins.drupal/site_template_helper true
    composer config --no-plugins allow-plugins.drupal/core-vendor-hardening true
    composer config --no-plugins allow-plugins.php-http/discovery true
    composer config --no-plugins allow-plugins.tbachert/spi false
}

if [ -n "$RESOLVE_VERSION" ]; then
    # DP_VERSION explicitly set — lock CMS version immediately
    log_info "Bootstrapping resolver project: ${RESOLVE_PROJECT}:${RESOLVE_VERSION} (mode ${MODE})"
    if [ "$MODE" = "4" ]; then
        create_project_with_version_fallback "$RESOLVE_PROJECT" "$RESOLVE_VERSION" "$TMP_DIR" "0"
    else
        create_project_with_version_fallback "$RESOLVE_PROJECT" "$RESOLVE_VERSION" "$TMP_DIR" "1"
    fi
    cd "$TMP_DIR"
    composer config --no-plugins minimum-stability dev
    composer config --no-plugins repositories.drupal composer https://packages.drupal.org/8
    configure_resolver_allow_plugins
else
    # DP_VERSION empty — init bare project, CMS added last after modules
    log_info "Bootstrapping bare resolver project for auto-detected CMS compatibility"
    mkdir -p "$TMP_DIR"
    cd "$TMP_DIR"
    composer init --no-interaction --name="drupalpod/temp-resolver" --type="project"
    composer config --no-plugins minimum-stability dev
    composer config --no-plugins prefer-stable true
    composer config --no-plugins repositories.drupal composer https://packages.drupal.org/8

    # allow-plugins required for drupal packages to install correctly
    configure_resolver_allow_plugins
fi

# Wire path repos for issue forks so resolver sees real code not Packagist
if [ -n "${DP_TEST_MODULE_ISSUE_FORK:-}" ] && [ -n "${DP_TEST_MODULE_ISSUE_BRANCH:-}" ]; then
    repo_path="$PROJECT_ROOT/repos/${DP_TEST_MODULE}"
    if [ -d "$repo_path" ]; then
        composer config --no-plugins repositories."${DP_TEST_MODULE}"-git \
            "{\"type\": \"path\", \"url\": \"$repo_path\", \"options\": {\"symlink\": true}}"
        log_info "Added path repository for issue fork: ${DP_TEST_MODULE}"
    else
        log_error "Issue fork repo not found at $repo_path — cannot proceed"
        exit 1
    fi
fi

if [ -n "${DP_AI_ISSUE_FORK:-}" ] && [ -n "${DP_AI_ISSUE_BRANCH:-}" ]; then
    repo_path="$PROJECT_ROOT/repos/${DP_AI_MODULE}"
    if [ -d "$repo_path" ]; then
        composer config --no-plugins repositories."${DP_AI_MODULE}"-git \
            "{\"type\": \"path\", \"url\": \"$repo_path\", \"options\": {\"symlink\": true}}"
        log_info "Added path repository for AI issue fork: ${DP_AI_MODULE}"
    else
        log_error "AI issue fork repo not found at $repo_path — cannot proceed"
        exit 1
    fi
fi

# Mode 1: strict solve first, escalate to Mode 4 only on dependency conflict.
if [ "$MODE" = "1" ]; then
    run_mode_one_strict_attempt
fi

# Mode 4: forced solve with scoped lenient plugin + with-all-dependencies.
# Only attempt force resolution if explicitly enabled via DP_FORCE_DEPENDENCIES=1.
if [ "$MODE" = "4" ]; then
    if [ "${FORCE_DEPENDENCIES}" = "1" ]; then
        run_mode_four_force_attempt
    else
        # Both AI and CMS are pinned but forcing is disabled - fail with clear error.
        log_error "Dependency conflict detected with both AI and CMS pinned"
        log_error "Set DP_FORCE_DEPENDENCIES=1 to enable lenient constraint resolution"
        write_error_manifest "$MANIFEST_FILE" "4" "error_unresolvable" \
            "${FORCED_REASON:-Incompatible version constraints without DP_FORCE_DEPENDENCIES=1}" \
            "${FORCED_REASON_LOG:-}" "$STARTER_TEMPLATE" "$DP_VERSION"
        exit 1
    fi
fi

# Baseline path (Modes 2/3 or any mode that did not resolve in helpers).
# Install required packages first (AI base + optional test module).
if [ "$PRIMARY_RESOLVED" = "0" ]; then
    for i in "${!REQUIRED_PACKAGES[@]}"; do
        composer require --prefer-dist -n --no-update "${REQUIRED_PACKAGES[$i]}:${REQUIRED_CONSTRAINTS[$i]}"
    done

    # Run initial update to resolve versions.
    composer -n update --no-install --no-progress
fi

# Lock in the resolved AI version if it wasn't explicit.
# This ensures optional modules resolve against a fixed
# base AI version.
if [ -z "${DP_AI_MODULE_VERSION:-}" ]; then
    resolved_ai_version=$(jq -r ".packages[] | select(.name==\"drupal/${DP_AI_MODULE}\") | .version" composer.lock | head -1)
    if [ -n "$resolved_ai_version" ] && [ "$resolved_ai_version" != "null" ]; then
        composer require --prefer-dist -n --no-update "drupal/${DP_AI_MODULE}:${resolved_ai_version}"
    fi
fi

# At this point, the base AI version is resolved.
echo "AI version resolved. Now trying optional modules..."

# Optional modules are "best effort": include only if cleanly compatible with the
# already-resolved base AI stack. We disable plugins to keep this check strict.
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

# Write final manifest plan with all requested packages.
ALL_REQUESTED=()
for package in "${REQUIRED_PACKAGES[@]}"; do
    if ! contains_package "$package" ${ALL_REQUESTED[@]+"${ALL_REQUESTED[@]}"}; then
        ALL_REQUESTED+=("$package")
    fi
done
for package in ${OPTIONAL_PACKAGES[@]+"${OPTIONAL_PACKAGES[@]}"}; do
    if ! contains_package "$package" ${ALL_REQUESTED[@]+"${ALL_REQUESTED[@]}"}; then
        ALL_REQUESTED+=("$package")
    fi
done

if [ "${#SKIPPED_PACKAGES[@]}" -gt 0 ]; then
    skipped_json=$(build_json_array "${SKIPPED_PACKAGES[@]}")
else
    skipped_json="[]"
fi

FILTERED_REQUESTED=()
for package in "${ALL_REQUESTED[@]}"; do
    if contains_package "$package" ${SKIPPED_PACKAGES[@]+"${SKIPPED_PACKAGES[@]}"}; then
        continue
    fi
    # Exclude CMS/Core project templates from module cloning list.
    # These are resolved for version detection only, not cloned as modules.
    if [ "$package" = "drupal/cms" ] || [ "$package" = "drupal/core-recommended" ]; then
        continue
    fi
    FILTERED_REQUESTED+=("$package")
done
requested_json=$(build_json_array "${FILTERED_REQUESTED[@]}")

if [ "$RESOLVE_PROJECT" = "drupal/recommended-project" ]; then
    RESOLVED_PROJECT_PACKAGE="drupal/core-recommended"
else
    RESOLVED_PROJECT_PACKAGE="$RESOLVE_PROJECT"
fi
# Read the resolved template package version from the lock context.
# composer show --self can return synthetic root versions (e.g. no-version-set),
# which are not valid install targets for create-project.
RESOLVED_PROJECT_VERSION_ACTUAL=$(composer show --locked --format=json "$RESOLVED_PROJECT_PACKAGE" 2>/dev/null | jq -r '.versions[0] // .version // empty' | head -1 || true)
if [ -z "$RESOLVED_PROJECT_VERSION_ACTUAL" ] || [[ "$RESOLVED_PROJECT_VERSION_ACTUAL" == *no-version-set* ]]; then
    RESOLVED_PROJECT_VERSION_ACTUAL=$(composer show --self --format=json 2>/dev/null | jq -r '.versions[0] // .version // empty' | head -1 || true)
fi
if [ -n "$RESOLVED_PROJECT_VERSION_ACTUAL" ]; then
    RESOLVED_PROJECT_VERSION_HINT="$RESOLVED_PROJECT_VERSION_ACTUAL"
else
    RESOLVED_PROJECT_VERSION_HINT="$RESOLVE_VERSION"
fi
if [[ "${RESOLVED_PROJECT_VERSION_HINT:-}" == *no-version-set* ]]; then
    RESOLVED_PROJECT_VERSION_HINT=""
fi

write_manifest_from_lock \
    "composer.lock" \
    "$requested_json" \
    "$skipped_json" \
    "$MANIFEST_FILE" \
    "$STARTER_TEMPLATE" \
    "$DP_VERSION" \
    "$RESOLVED_PROJECT_PACKAGE" \
    "$RESOLVED_PROJECT_VERSION_HINT" \
    "$MODE" \
    "$COMPATIBILITY" \
    "$FORCED_REASON" \
    "$FORCED_REASON_LOG" \
    "drupal/${DP_AI_MODULE}" \
    "${DP_AI_ISSUE_BRANCH:-}" \
    "drupal/${DP_TEST_MODULE:-}" \
    "${DP_TEST_MODULE_ISSUE_BRANCH:-}"

if [ -z "${DP_VERSION:-}" ] && [ "${STARTER_TEMPLATE:-cms}" = "cms" ]; then
    # Guard: auto-detect must always materialize to a concrete CMS version.
    RESOLVED_CMS=$(jq -r '.resolved_cms_version // ""' "$MANIFEST_FILE")
    if [ -z "$RESOLVED_CMS" ] || [ "$RESOLVED_CMS" = "null" ] || [[ "$RESOLVED_CMS" == *no-version-set* ]]; then
        log_error "Auto-detect failed: resolved_cms_version is empty in manifest"
        exit 1
    fi
    log_info "Auto-detected CMS version: $RESOLVED_CMS"
fi

# Final output.
log_info "Resolved AI module plan written to: $MANIFEST_FILE"
