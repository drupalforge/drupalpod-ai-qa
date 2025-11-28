#!/usr/bin/env bash
set -eu -o pipefail
cd "${APP_ROOT}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Clone AI Modules from Git (Dependency-Driven Architecture)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Automatically clones AI base module + dependencies from git.drupalcode.org
# Supports version branches, tags, and PR testing
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Track which modules we clone and which are compatible
export CLONED_AI_MODULES=""
export COMPATIBLE_AI_MODULES=""  # Only modules compatible with AI version

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Helper: Clone a module from git
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
clone_module() {
    local module_name=$1
    local module_version=${2:-}
    local issue_fork=${3:-}
    local issue_branch=${4:-}

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Cloning: $module_name"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    if git submodule status repos/"$module_name" > /dev/null 2>&1; then
        echo "  ✓ Submodule exists, updating..."
        time git submodule update --init --recursive repos/"$module_name"
    else
        echo "  + Adding as submodule..."
        time git submodule add -f https://git.drupalcode.org/project/"$module_name".git repos/"$module_name"
        time git config -f .gitmodules submodule."repos/$module_name".ignore dirty
    fi

    cd "${APP_ROOT}"/repos/"$module_name"
    git fetch origin
    git fetch --all --tags

    # Checkout specific PR/issue branch if specified
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
        # Check if it's a branch (*.x)
        if [[ "$module_version" == *.x ]]; then
            if git show-ref --verify --quiet refs/remotes/origin/"$module_version"; then
                git checkout -B "$module_version" origin/"$module_version"
            else
                echo "  ⚠️  Branch $module_version not found, using latest stable"
                latest_tag=$(git describe --tags --abbrev=0 $(git rev-list --tags --max-count=1) 2>/dev/null || true)
                if [ -n "$latest_tag" ]; then
                    git checkout tags/"$latest_tag"
                fi
            fi
        else
            # Try as tag, then branch
            if git rev-parse tags/"$module_version" >/dev/null 2>&1; then
                git checkout tags/"$module_version"
            elif git show-ref --verify --quiet refs/remotes/origin/"$module_version"; then
                git checkout -B "$module_version" origin/"$module_version"
            else
                echo "  ⚠️  Version $module_version not found, using latest stable"
                latest_tag=$(git describe --tags --abbrev=0 $(git rev-list --tags --max-count=1) 2>/dev/null || true)
                if [ -n "$latest_tag" ]; then
                    git checkout tags/"$latest_tag"
                fi
            fi
        fi
    else
        # No version specified - checkout latest stable tag
        echo "  → No version specified, checking out latest stable release"
        latest_tag=$(git describe --tags --abbrev=0 $(git rev-list --tags --max-count=1) 2>/dev/null || true)
        if [ -n "$latest_tag" ]; then
            echo "  → Found latest stable: $latest_tag"
            git checkout tags/"$latest_tag"
        else
            echo "  ⚠️  No tags found, using default branch"
        fi
    fi

    cd "${APP_ROOT}"

    # Add to cloned modules list
    if [ -z "$CLONED_AI_MODULES" ]; then
        export CLONED_AI_MODULES="$module_name"
    else
        export CLONED_AI_MODULES="$CLONED_AI_MODULES,$module_name"
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Helper: Get AI ecosystem dependencies from composer.json
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
get_ai_dependencies() {
    local module_path=$1
    local composer_json="${module_path}/composer.json"

    if [ ! -f "$composer_json" ]; then
        return
    fi

    # Extract drupal/ai* dependencies from require section
    # Use grep and sed to parse JSON (simple approach)
    grep -A 100 '"require"' "$composer_json" | \
        grep '"drupal/ai' | \
        sed 's/.*"drupal\/\([^"]*\)".*/\1/' || true
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Helper: Extract compatible version from constraint
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
get_compatible_version() {
    local module_path=$1
    local dependency_name=$2
    local composer_json="${module_path}/composer.json"

    if [ ! -f "$composer_json" ]; then
        echo ""
        return
    fi

    # Extract version constraint for the dependency
    # e.g., "drupal/ai_provider_litellm": "^1.2" → return "1.2.x"
    local constraint=$(grep -A 100 '"require"' "$composer_json" | \
        grep "\"drupal/$dependency_name\"" | \
        sed 's/.*"drupal\/[^"]*": *"\([^"]*\)".*/\1/' | \
        head -1 || true)

    if [ -z "$constraint" ]; then
        echo ""
        return
    fi

    # Convert constraint to branch version
    # ^1.2 → 1.2.x
    # ^1.2.0 → 1.2.x
    # ~1.2.0 → 1.2.x
    local version=$(echo "$constraint" | sed -E 's/[\^~>=<]//g' | sed -E 's/^([0-9]+\.[0-9]+).*/\1.x/')
    echo "$version"
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Helper: Check if module is compatible with AI version
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
is_compatible_with_ai() {
    local module_path=$1
    local ai_version=$2

    # If AI version is empty (using git default branch), we can't check compatibility
    # Assume compatible - the actual version will be determined by git
    if [ -z "$ai_version" ]; then
        return 0  # Can't check compatibility without knowing AI version
    fi

    local composer_json="${module_path}/composer.json"

    if [ ! -f "$composer_json" ]; then
        return 0  # If no composer.json, assume compatible
    fi

    # Get the AI requirement constraint (e.g., "^2.0", "^1.2")
    local ai_constraint=$(grep -A 100 '"require"' "$composer_json" | \
        grep '"drupal/ai"' | \
        sed 's/.*"drupal\/ai": *"\([^"]*\)".*/\1/' | \
        head -1 || true)

    if [ -z "$ai_constraint" ]; then
        return 0  # If no AI requirement, assume compatible
    fi

    # Extract major.minor from constraint (e.g., ^2.0 → 2.0, ^1.2 → 1.2)
    local required_version=$(echo "$ai_constraint" | sed -E 's/[\^~>=<]//g' | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')

    # Extract major.minor from our AI version (e.g., 1.2.x → 1.2, 2.0.x → 2.0)
    local our_version=$(echo "$ai_version" | sed -E 's/^([0-9]+\.[0-9]+).*/\1/')

    # Simple version comparison: they must match
    if [ "$required_version" = "$our_version" ]; then
        return 0  # Compatible
    else
        echo "  ⚠️  Incompatible: requires AI ^$required_version, but we have AI $ai_version" >&2
        return 1  # Incompatible
    fi
}

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Main Logic: Hybrid Architecture (Dependency-Driven)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# 1. If DP_TEST_MODULE set: Clone test module first, read AI requirement from composer.json
# 2. If DP_AI_MODULE_VERSION set: Use that specific version (dev branch or tag)
# 3. Otherwise: Use latest stable tag (e.g., 1.2.1, not 1.2.x-dev)
# 4. Clone additional modules from DP_AI_MODULES with compatibility filtering
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

# Determine final AI version to use (empty = latest stable tag)
FINAL_AI_VERSION="${DP_AI_MODULE_VERSION}"

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 1: Clone test module first (if specified) to determine AI requirements
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
if [ -n "${DP_TEST_MODULE:-}" ]; then
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 1: Clone Test Module (determines AI version requirement)"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

    test_version="$DP_TEST_MODULE_VERSION"
    clone_module "$DP_TEST_MODULE" "$test_version" "$DP_TEST_MODULE_ISSUE_FORK" "$DP_TEST_MODULE_ISSUE_BRANCH"

    # Get AI requirement from test module
    test_module_ai_requirement=$(get_compatible_version "repos/$DP_TEST_MODULE" "$DP_AI_MODULE")

    if [ -n "$test_module_ai_requirement" ]; then
        # Check if user explicitly set AI version
        if [ "${DP_AI_MODULE_VERSION_EXPLICIT:-no}" = "yes" ]; then
            # User explicitly set AI version - validate compatibility
            if [ "$test_module_ai_requirement" != "$FINAL_AI_VERSION" ]; then
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo "❌ ERROR: Version Conflict"
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                echo ""
                echo "Test module '$DP_TEST_MODULE' requires AI $test_module_ai_requirement"
                echo "But you explicitly configured DP_AI_MODULE_VERSION=$FINAL_AI_VERSION"
                echo ""
                echo "Fix options:"
                echo "  1. Remove DP_AI_MODULE_VERSION from config (auto-detect from test module)"
                echo "  2. Change DP_AI_MODULE_VERSION to $test_module_ai_requirement"
                echo "  3. Test a different module compatible with AI $FINAL_AI_VERSION"
                echo ""
                echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
                exit 1
            else
                echo "  ✓ Test module requires AI $test_module_ai_requirement (matches your configuration)"
            fi
        else
            # User didn't set AI version - auto-detect from test module
            FINAL_AI_VERSION="$test_module_ai_requirement"
            echo "  → Test module requires AI $FINAL_AI_VERSION (auto-detected)"
        fi
    else
        # Couldn't determine requirement from test module
        if [ "${DP_AI_MODULE_VERSION_EXPLICIT:-no}" = "no" ]; then
            echo "  ⚠️  Could not determine AI version from test module's composer.json"
            if [ -z "$FINAL_AI_VERSION" ]; then
                echo "  → Using git repo's default branch (future-proof)"
            else
                echo "  → Using default: $FINAL_AI_VERSION"
            fi
        else
            echo "  ⚠️  Could not determine AI version from test module's composer.json"
            echo "  → Using your configured version: $FINAL_AI_VERSION"
        fi
    fi

    # Mark test module as compatible (it drove the AI version choice)
    if [ -z "$COMPATIBLE_AI_MODULES" ]; then
        export COMPATIBLE_AI_MODULES="$DP_TEST_MODULE"
    else
        export COMPATIBLE_AI_MODULES="$COMPATIBLE_AI_MODULES,$DP_TEST_MODULE"
    fi
else
    echo
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "Step 1: No Test Module"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    if [ -z "$FINAL_AI_VERSION" ]; then
        echo "  → Will use latest stable release tag"
    else
        echo "  → Using explicitly configured AI version: $FINAL_AI_VERSION"
    fi
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 2: Clone AI base module at determined version
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
if [ -z "$FINAL_AI_VERSION" ]; then
    echo "Step 2: Clone AI Base Module @ latest stable"
else
    echo "Step 2: Clone AI Base Module @ $FINAL_AI_VERSION"
fi
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

clone_module "$DP_AI_MODULE" "$FINAL_AI_VERSION" "$DP_AI_ISSUE_FORK" "$DP_AI_ISSUE_BRANCH"

# If AI version was empty (latest stable tag), detect the actual version for compatibility filtering
if [ -z "$FINAL_AI_VERSION" ]; then
    cd "${APP_ROOT}"/repos/"$DP_AI_MODULE"

    # Try multiple methods to detect version
    # Method 1: Current branch name (works if checked out to a branch)
    actual_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || true)

    if [[ "$actual_branch" =~ ^[0-9]+\.[0-9x]+$ ]] || [[ "$actual_branch" =~ ^[0-9]+\.x$ ]]; then
        FINAL_AI_VERSION="$actual_branch"
        echo "  → Detected AI version from branch: $FINAL_AI_VERSION"
    else
        # Method 2: Check which remote branch this commit belongs to (handles detached HEAD)
        remote_branch=$(git branch -r --contains HEAD 2>/dev/null | grep -E 'origin/[0-9]+\.(x|[0-9]+\.x)$' | head -1 | xargs | sed 's|.*origin/||' || true)

        if [ -n "$remote_branch" ] && [[ "$remote_branch" =~ ^[0-9]+\.[0-9x]+$ ]]; then
            FINAL_AI_VERSION="$remote_branch"
            echo "  → Detected AI version from remote branch: $FINAL_AI_VERSION"
        else
            # Method 3: Try git describe to find nearest tag
            nearest_tag=$(git describe --tags --abbrev=0 2>/dev/null || true)
            if [ -n "$nearest_tag" ]; then
                # Convert tag to branch format (e.g., 1.2.0 → 1.2.x, 2.0.0-alpha1 → 2.0.x)
                FINAL_AI_VERSION=$(echo "$nearest_tag" | sed -E 's/^([0-9]+\.[0-9]+).*/\1.x/')
                echo "  → Detected AI version from tag: $FINAL_AI_VERSION (from $nearest_tag)"
            fi
        fi
    fi

    cd "${APP_ROOT}"

    if [ -n "$FINAL_AI_VERSION" ]; then
        echo "  ✓ Using detected version for compatibility filtering: $FINAL_AI_VERSION"
    else
        echo "  ⚠️  Could not detect AI version - skipping compatibility filtering"
    fi
fi

# AI base is always compatible
if [ -z "$COMPATIBLE_AI_MODULES" ]; then
    export COMPATIBLE_AI_MODULES="$DP_AI_MODULE"
else
    export COMPATIBLE_AI_MODULES="$COMPATIBLE_AI_MODULES,$DP_AI_MODULE"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 3: Clone additional AI modules (with compatibility filtering)
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 3: Clone Additional AI Modules (compatibility filtering)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Parse DP_AI_MODULES (comma-separated list)
if [ -n "${DP_AI_MODULES:-}" ]; then
    IFS=',' read -ra MODULES <<< "$DP_AI_MODULES"
    for module in "${MODULES[@]}"; do
        module=$(echo "$module" | xargs)  # Trim whitespace

        if [ -z "$module" ]; then
            continue
        fi

        # Skip if already cloned (e.g., as test module)
        if echo ",$CLONED_AI_MODULES," | grep -q ",$module,"; then
            echo "  ✓ $module already cloned"
            continue
        fi

        # Clone at dev branch
        echo "  → Cloning $module..."
        clone_module "$module" ""

        # Check compatibility with AI version
        if is_compatible_with_ai "repos/$module" "$FINAL_AI_VERSION"; then
            echo "  ✓ $module is compatible with AI $FINAL_AI_VERSION"
            if [ -z "$COMPATIBLE_AI_MODULES" ]; then
                export COMPATIBLE_AI_MODULES="$module"
            else
                export COMPATIBLE_AI_MODULES="$COMPATIBLE_AI_MODULES,$module"
            fi
        else
            echo "  ✗ Skipping $module from composer (incompatible, but cloned for inspection)"
        fi
    done
else
    echo "  (No additional modules specified in DP_AI_MODULES)"
fi

# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# Step 4: Clone default provider
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Step 4: Clone Default Provider"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Always clone ai_provider_litellm unless already cloned
if echo ",$CLONED_AI_MODULES," | grep -q ",ai_provider_litellm,"; then
    echo "  ✓ Provider already cloned"
else
    provider_version=$(get_compatible_version "repos/$DP_AI_MODULE" "ai_provider_litellm")
    if [ -z "$provider_version" ]; then
        provider_version="$FINAL_AI_VERSION"
    fi
    echo "  → Cloning default provider: ai_provider_litellm @ $provider_version"
    clone_module "ai_provider_litellm" "$provider_version"

    # Check compatibility
    if is_compatible_with_ai "repos/ai_provider_litellm" "$FINAL_AI_VERSION"; then
        echo "  ✓ Provider is compatible"
        export COMPATIBLE_AI_MODULES="$COMPATIBLE_AI_MODULES,ai_provider_litellm"
    else
        echo "  ✗ Provider incompatible (skipping from composer)"
    fi
fi

echo
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✓ Summary"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  AI Version: $FINAL_AI_VERSION"
echo "  Cloned modules: $CLONED_AI_MODULES"
echo "  Compatible (will be added to composer): $COMPATIBLE_AI_MODULES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo
