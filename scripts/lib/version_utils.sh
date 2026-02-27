#!/usr/bin/env bash
# Version normalization utilities for DrupalPod AI QA scripts.
# Handles conversions between Composer versions, Git refs, and user input.

# Normalize Composer version strings to Git-compatible versions.
# Direction: Composer-resolved version -> git ref/branch/tag.
# Examples:
#   dev-1.x       -> 1.x
#   1.2.x-dev    -> 1.2.x
#   1.2.3-dev    -> 1.2.3
#   1.2.3        -> 1.2.3
normalize_composer_version_to_git() {
    local version=${1:-}

    if [ -z "$version" ]; then
        echo ""
        return
    fi

    if [[ "$version" == dev-* ]]; then
        echo "${version#dev-}"
        return
    fi

    if [[ "$version" =~ ^([0-9]+\.[0-9]+)\.x-dev$ ]]; then
        echo "${BASH_REMATCH[1]}.x"
        return
    fi

    if [[ "$version" == *-dev ]]; then
        echo "${version%-dev}"
        return
    fi

    echo "$version"
}

# Normalize version input to a Composer constraint.
# Examples:
#   ""        -> "*"
#   "1"       -> "^1"
#   "1.2"     -> "~1.2"
#   "1.x"     -> "1.x-dev"
#   "1.2.x"   -> "1.2.x-dev"
#   "1.2.3"   -> "1.2.3"
normalize_version_to_composer() {
    local version=${1:-}

    if [ -z "$version" ]; then
        echo "*"
        return
    fi

    if [[ "$version" =~ ^[0-9]+$ ]]; then
        echo "^$version"
        return
    fi

    if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "~$version"
        return
    fi

    if [[ "$version" =~ ^[0-9]+\.x$ ]]; then
        echo "${version}-dev"
        return
    fi

    if [[ "$version" == *.x ]]; then
        echo "${version}-dev"
        return
    fi

    echo "$version"
}

# Normalize user-provided version input to a git ref-like string.
normalize_version_to_git_ref() {
    local version=${1:-}

    if [ -z "$version" ]; then
        echo ""
        return
    fi

    # Strip leading composer operators.
    version="${version#^}"
    version="${version#~}"

    if [[ "$version" =~ ^[0-9]+$ ]]; then
        echo "${version}.x"
        return
    fi

    if [[ "$version" =~ ^[0-9]+\.[0-9]+$ ]]; then
        echo "${version}.x"
        return
    fi

    echo "$version"
}
