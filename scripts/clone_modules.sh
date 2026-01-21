#!/usr/bin/env bash
set -eu -o pipefail

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Clone AI Modules from Git (Composer-resolved).
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Load common utilities (skip if already loaded by parent script).
if [ -z "${SCRIPT_DIR:-}" ]; then
    export SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
    source "$SCRIPT_DIR/lib/common.sh"
    init_common
fi
require_jq

cd "$PROJECT_ROOT"

# Track which modules were cloned and which were added to Composer.
export CLONED_MODULES=""
export COMPATIBLE_MODULES=""

# Clone or update a module submodule and check out the right ref.
clone_module() {
    local module_name=$1
    local module_version=${2:-}
    local issue_fork=${3:-}
    local issue_branch=${4:-}

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Cloning: $module_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    # Check if the module is already cloned.
    if git submodule status repos/"$module_name" > /dev/null 2>&1; then
        echo "  ✓ Submodule exists, updating..."
        # time git submodule update --init --recursive repos/"$module_name"
    else
        echo "  + Adding as submodule..."
        time git submodule add -f https://git.drupalcode.org/project/"$module_name".git repos/"$module_name"
        time git config -f .gitmodules submodule."repos/$module_name".ignore dirty
    fi

    # Navigate to module repo and fetch updates.
    cd "$PROJECT_ROOT/repos/$module_name"
    # git fetch --all --tags

    # Determine checkout target: PR branch, specific version, or latest stable.
    if [ -n "$issue_branch" ] && [ -n "$issue_fork" ]; then
        echo "  → Checking out PR: $issue_fork/$issue_branch"
        if git show-ref -q --heads "$issue_branch"; then
            git checkout "$issue_branch"
        else
            git remote add issue-"$issue_fork" https://git.drupalcode.org/issue/"$issue_fork".git 2>/dev/null || true
            git fetch issue-"$issue_fork"
            git checkout -b "$issue_branch" --track issue-"$issue_fork"/"$issue_branch"
        fi
    elif [ -n "$module_version" ]; then
        echo "  → Checking out version: $module_version"
        if [[ "$module_version" == *.x ]]; then
            if git show-ref --verify --quiet refs/remotes/origin/"$module_version"; then
                git checkout -B "$module_version" origin/"$module_version"
            else
                echo "  ⚠️ Branch $module_version not found, using latest stable"
                latest_tag=$(git tag --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
                if [ -n "$latest_tag" ]; then
                    git checkout tags/"$latest_tag"
                fi
            fi
        else
            if git rev-parse tags/"$module_version" >/dev/null 2>&1; then
                git checkout tags/"$module_version"
            elif git show-ref --verify --quiet refs/remotes/origin/"$module_version"; then
                git checkout -B "$module_version" origin/"$module_version"
            else
                echo "  ⚠️ Version $module_version not found, using latest stable"
                latest_tag=$(git tag --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
                if [ -n "$latest_tag" ]; then
                    git checkout tags/"$latest_tag"
                fi
            fi
        fi
    else
        echo "  → No version specified, checking out latest stable release"
        latest_tag=$(git tag --sort=-version:refname | grep -E '^[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)
        if [ -n "$latest_tag" ]; then
            echo "  → Found latest stable: $latest_tag"
            git checkout tags/"$latest_tag"
        else
            echo "  ⚠️ No tags found, using default branch"
        fi
    fi

    cd "$PROJECT_ROOT"

    if [ -z "$CLONED_MODULES" ]; then
        export CLONED_MODULES="$module_name"
    else
        export CLONED_MODULES="$CLONED_MODULES,$module_name"
    fi
}

# Read "requested" modules from the plan with their resolved versions.
load_manifest_modules() {
    local manifest_file=$1
    jq -r '.packages[] | "\(.name) \(.version)"' "$manifest_file"
}

# Read modules that were skipped due to incompatibility.
load_manifest_skipped_modules() {
    local manifest_file=$1
    jq -r '.skipped_packages[]? // empty' "$manifest_file"
}

# Prevent duplicate clones when a module appears in both lists.
is_cloned() {
    local module_name=$1
    if [ -z "$CLONED_MODULES" ]; then
        return 1
    fi
    echo ",$CLONED_MODULES," | grep -q ",$module_name,"
}

# The resolver writes a manifest file; cloning follows that plan.
if [ ! -f "$MANIFEST_FILE" ]; then
    echo "ERROR: Module manifest not found: $MANIFEST_FILE" >&2
    echo "Run scripts/resolve_modules.sh before cloning." >&2
    exit 1
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Clone modules from Composer-resolved plan.
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Clone all modules in the resolution plan (with resolved versions).
# Each plan entry is a "drupal/foo version" pair from composer.lock.
while read -r package version; do
    module_name=$(strip_drupal_prefix "$package")
    git_version=$(normalize_composer_version_to_git "$version")

    issue_fork=""
    issue_branch=""

    # Allow PR overrides for base AI module or a test module.
    if [ "$module_name" = "${DP_AI_MODULE}" ]; then
        issue_fork="${DP_AI_ISSUE_FORK:-}"
        issue_branch="${DP_AI_ISSUE_BRANCH:-}"
    fi

    if [ -n "${DP_TEST_MODULE:-}" ] && [ "$module_name" = "${DP_TEST_MODULE}" ]; then
        issue_fork="${DP_TEST_MODULE_ISSUE_FORK:-}"
        issue_branch="${DP_TEST_MODULE_ISSUE_BRANCH:-}"
    fi

    # Clone the module and record it as compatible for composer setup.
    clone_module "$module_name" "$git_version" "$issue_fork" "$issue_branch"

    # Ensure PR branches satisfy Composer constraints.
    apply_branch_alias() {
        local repo_dir=$1
        local branch=$2
        local alias=$3
        local composer_json="$repo_dir/composer.json"

        if [ -f "$composer_json" ]; then
            log_info "Applying branch alias: dev-$branch -> $alias"
            jq --arg version "dev-$branch" \
               --arg branch "dev-$branch" \
               --arg alias "$alias" \
               '.version = $version
                | .extra["branch-alias"] = (.extra["branch-alias"] // {})
                | .extra["branch-alias"][$branch] = $alias' \
               "$composer_json" > "$composer_json.tmp" && mv "$composer_json.tmp" "$composer_json"
        fi
    }

    if [ -n "$issue_branch" ]; then
        if [ "$module_name" = "${DP_AI_MODULE}" ] && [ -n "${DP_AI_MODULE_VERSION:-}" ]; then
            apply_branch_alias "$PROJECT_ROOT/repos/$module_name" "$issue_branch" "${DP_AI_MODULE_VERSION}-dev"
            if [ -z "${DP_ALIAS_MODULES:-}" ]; then
                export DP_ALIAS_MODULES="$module_name"
            else
                export DP_ALIAS_MODULES="$DP_ALIAS_MODULES,$module_name"
            fi
        elif [ "$module_name" = "${DP_TEST_MODULE:-}" ] && [ -n "${DP_TEST_MODULE_VERSION:-}" ]; then
            apply_branch_alias "$PROJECT_ROOT/repos/$module_name" "$issue_branch" "${DP_TEST_MODULE_VERSION}-dev"
            if [ -z "${DP_ALIAS_MODULES:-}" ]; then
                export DP_ALIAS_MODULES="$module_name"
            else
                export DP_ALIAS_MODULES="$DP_ALIAS_MODULES,$module_name"
            fi
        fi
    fi

    if [ -z "$COMPATIBLE_MODULES" ]; then
        export COMPATIBLE_MODULES="$module_name"
    else
        export COMPATIBLE_MODULES="$COMPATIBLE_MODULES,$module_name"
    fi

done < <(load_manifest_modules "$MANIFEST_FILE")

# Clone skipped modules too (available in repos/ but not in composer).
# This keeps local checkouts handy even if they were incompatible.
while read -r skipped_package; do
    module_name=$(strip_drupal_prefix "$skipped_package")
    if is_cloned "$module_name"; then
        continue
    fi
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Cloning skipped module: $module_name (not added to composer)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    clone_module "$module_name" ""
done < <(load_manifest_skipped_modules "$MANIFEST_FILE")

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  Manifest: $MANIFEST_FILE"
echo "  Cloned modules: $CLONED_MODULES"
echo "  Composer modules: $COMPATIBLE_MODULES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
