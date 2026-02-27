#!/usr/bin/env bash

# Resolution mode constants.
# 1: AI/test module pinned, CMS not pinned (auto-detect CMS via solver).
# 2: CMS pinned, AI/test not pinned.
# 3: Neither CMS nor AI/test pinned (fully auto).
# 4: CMS pinned and AI/test pinned (force path eligible on conflicts).
MODE_AI_AND_CMS_PINNED=4
MODE_AI_PINNED=1
MODE_CMS_PINNED=2
MODE_AUTO=3

# Select resolver mode from normalized version inputs.
# Inputs must be normalized composer constraints where "*" means unset.
select_mode() {
    local normalized_ai_version=$1
    local normalized_cms_version=$2
    local normalized_test_module_version=${3:-"*"}
    local ai_issue_branch=${4:-""}
    local test_issue_branch=${5:-""}
    local ai_set=0
    local cms_set=0

    if [ "$normalized_ai_version" != "*" ]; then
        ai_set=1
    fi
    if [ "$normalized_test_module_version" != "*" ]; then
        ai_set=1
    fi
    if [ -n "$ai_issue_branch" ] || [ -n "$test_issue_branch" ]; then
        # Issue branches are treated as pins because they fix code under test.
        ai_set=1
    fi
    if [ "$normalized_cms_version" != "*" ]; then
        cms_set=1
    fi

    if [ "$ai_set" -eq 1 ] && [ "$cms_set" -eq 1 ]; then
        echo "$MODE_AI_AND_CMS_PINNED"
    elif [ "$ai_set" -eq 1 ] && [ "$cms_set" -eq 0 ]; then
        echo "$MODE_AI_PINNED"
    elif [ "$ai_set" -eq 0 ] && [ "$cms_set" -eq 1 ]; then
        echo "$MODE_CMS_PINNED"
    else
        echo "$MODE_AUTO"
    fi
}

# Classify composer failure output conservatively.
classify_composer_failure() {
    local output=$1

    if printf '%s' "$output" | grep -Eq "Could not connect|Failed to download|curl error|SSL|403|401|DNS|don't have the right to access|Permission denied"; then
        echo "error_infra"
    elif printf '%s' "$output" | grep -Fq "Your requirements could not be resolved"; then
        echo "dependency_conflict"
    else
        echo "error_infra"
    fi
}
