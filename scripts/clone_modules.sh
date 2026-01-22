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

# Override a resolved git ref with an explicit module version.
override_git_version() {
    local module_name=$1
    local current_version=$2
    local override_version=$3
    local label=$4

    if [ -n "$override_version" ]; then
        log_info "Using ${label} for ${module_name}: ${override_version}"
        echo "$(normalize_version_to_git_ref "$override_version")"
        return
    fi

    echo "$current_version"
}

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
         # Ensure local composer.json edits don't block checkouts.
        if ! git -C "$PROJECT_ROOT/repos/$module_name" diff --quiet -- composer.json; then
            git -C "$PROJECT_ROOT/repos/$module_name" checkout -- composer.json
        fi
    else
        echo "  + Adding as submodule..."
        time git submodule add -f https://git.drupalcode.org/project/"$module_name".git repos/"$module_name"
        time git config -f .gitmodules submodule."repos/$module_name".ignore dirty
    fi

    # Sync the submodule to ensure it's initialized.
    echo "  → Syncing submodule directory..."
    time git submodule update --init --recursive repos/"$module_name"

    # Navigate to module repo and fetch updates.
    cd "$PROJECT_ROOT/repos/$module_name"
    if ! git fetch origin --tags --prune; then
        log_warn "git fetch origin failed (auth or network). Continuing with existing refs."
    fi

    # Validate that both issue branch and fork are provided together.
    if [ -n "$issue_branch" ] && [ -z "$issue_fork" ]; then
        echo "ERROR: Issue branch specified for $module_name ($issue_branch) but no fork provided." >&2
        echo "Set DP_AI_ISSUE_FORK or DP_TEST_MODULE_ISSUE_FORK." >&2
        exit 1
    fi

    if [ -n "$issue_fork" ] && [ -z "$issue_branch" ]; then
        echo "ERROR: Fork specified for $module_name ($issue_fork) but no issue branch provided." >&2
        echo "Set DP_AI_ISSUE_BRANCH or DP_TEST_MODULE_ISSUE_BRANCH." >&2
        exit 1
    fi

    # Determine checkout target: PR branch, specific version, or latest stable.
    if [ -n "$issue_branch" ] && [ -n "$issue_fork" ]; then
        echo "  → Checking out PR: $issue_fork/$issue_branch"
        git remote add issue-"$issue_fork" https://git.drupalcode.org/issue/"$issue_fork".git 2>/dev/null || true
        if ! git fetch issue-"$issue_fork"; then
            log_warn "git fetch failed for issue-$issue_fork. Continuing with existing refs."
        fi
        if ! git show-ref --verify --quiet refs/remotes/issue-"$issue_fork"/"$issue_branch"; then
            echo "ERROR: Branch $issue_branch not found on fork $issue_fork." >&2
            exit 1
        fi
        git checkout -B "$issue_branch" issue-"$issue_fork"/"$issue_branch"
        git branch --set-upstream-to=issue-"$issue_fork"/"$issue_branch" "$issue_branch" >/dev/null 2>&1 || true
    elif [ -n "$module_version" ]; then
        echo "  → Checking out version: $module_version"
        if [[ "$module_version" == *.x ]]; then
            if git show-ref --verify --quiet refs/remotes/origin/"$module_version"; then
                git checkout -B "$module_version" origin/"$module_version"
            else
                echo "ERROR: Branch $module_version not found on origin." >&2
                exit 1
            fi
        else
            if git rev-parse tags/"$module_version" >/dev/null 2>&1; then
                git checkout tags/"$module_version"
            elif git show-ref --verify --quiet refs/remotes/origin/"$module_version"; then
                git checkout -B "$module_version" origin/"$module_version"
            else
                echo "ERROR: Version $module_version not found on origin." >&2
                exit 1
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
    if [ "$module_name" = "${DP_AI_MODULE}" ]; then
        git_version=$(override_git_version "$module_name" "$git_version" "${DP_AI_MODULE_VERSION:-}" "DP_AI_MODULE_VERSION")
    elif [ -n "${DP_TEST_MODULE:-}" ] && [ "$module_name" = "${DP_TEST_MODULE}" ]; then
        git_version=$(override_git_version "$module_name" "$git_version" "${DP_TEST_MODULE_VERSION:-}" "DP_TEST_MODULE_VERSION")
    fi

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
            log_info "Applying branch alias for constraint checks: dev-$branch -> $alias"
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
            if [ "${DP_FORCE_DEPENDENCIES:-0}" = "1" ]; then
                continue
            fi
            alias_target="${DP_AI_MODULE_VERSION}-dev"

            apply_branch_alias "$PROJECT_ROOT/repos/$module_name" "$issue_branch" "$alias_target"
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
