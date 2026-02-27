#!/usr/bin/env bash

# Mode 1 strict attempt:
# - Try normal Composer resolution first (no lenient plugin).
# - If dependencies conflict, escalate to Mode 4.
# - If infra/auth/network fails, stop and emit an error manifest.
run_mode_one_strict_attempt() {
    local require_args=()
    local normalized_test_version=""
    local should_require_test_module=0
    local ai_constraint="$NORMALIZED_AI_VERSION"
    local test_constraint=""

    if [ -n "${DP_AI_ISSUE_BRANCH:-}" ] && [ "$NORMALIZED_AI_VERSION" = "*" ]; then
        ai_constraint="*@dev"
    fi

    require_args=("drupal/${DP_AI_MODULE}:${ai_constraint}")
    normalized_test_version="$(normalize_version_to_composer "${DP_TEST_MODULE_VERSION:-}")"
    test_constraint="$normalized_test_version"
    if [ -n "${DP_TEST_MODULE:-}" ]; then
        if [ "$normalized_test_version" != "*" ] || [ -n "${DP_TEST_MODULE_ISSUE_BRANCH:-}" ]; then
            should_require_test_module=1
        fi
    fi
    if [ -n "${DP_TEST_MODULE_ISSUE_BRANCH:-}" ] && [ "$normalized_test_version" = "*" ]; then
        test_constraint="*@dev"
    fi
    if [ "$should_require_test_module" -eq 1 ]; then
        require_args+=("drupal/${DP_TEST_MODULE}:${test_constraint}")
    fi

    # For CMS auto-detect, include drupal/cms in the same require call so the
    # solver picks a compatible CMS line alongside pinned module constraints.
    if [ -z "${DP_VERSION:-}" ] && [ "${STARTER_TEMPLATE:-cms}" = "cms" ]; then
        require_args+=("drupal/cms")
    fi

    set +e
    COMPOSER_OUT=$(composer require --no-interaction "${require_args[@]}" 2>&1)
    COMPOSER_EXIT=$?
    set -e

    if [ "$COMPOSER_EXIT" -eq 0 ]; then
        PRIMARY_RESOLVED=1
        return
    fi

    CLASSIFICATION=$(classify_composer_failure "$COMPOSER_OUT")
    if [ "$COMPOSER_EXIT" -eq 2 ] && [ "$CLASSIFICATION" = "dependency_conflict" ]; then
        printf '%s\n' "$COMPOSER_OUT"
        log_warn "Clean resolve failed — escalating to Mode 4"
        MODE=4
        FORCED_REASON_LOG="$LOG_DIR/resolve-failure.log"
        printf '%s\n' "$COMPOSER_OUT" > "$FORCED_REASON_LOG"
        FORCED_REASON=$(printf '%s\n' "$COMPOSER_OUT" | awk '
            /^  Problem 1/ {in_problem=1; next}
            in_problem && /^    - / {sub(/^    - /, ""); print; exit}
            in_problem && !/^    / {in_problem=0}
        ')
        if [ -z "$FORCED_REASON" ]; then
            FORCED_REASON=$(printf '%s\n' "$COMPOSER_OUT" | grep -m1 "Problem 1" || true)
        fi
        if [ -z "$FORCED_REASON" ]; then
            FORCED_REASON=$(printf '%s\n' "$COMPOSER_OUT" | grep -m1 "Your requirements could not be resolved" || true)
        fi
        [ -n "$FORCED_REASON" ] || FORCED_REASON="Dependency conflict during clean resolve"
        return
    fi

    printf '%s\n' "$COMPOSER_OUT"
    log_error "Infrastructure failure — cannot proceed"
    write_error_manifest "$MANIFEST_FILE" "1" "error_infra" "" "" "$STARTER_TEMPLATE" "$DP_VERSION"
    exit 1
}

# Mode 4 force attempt:
# apply lenient constraint rewriting only to pinned/local modules and run a
# final require with --with-all-dependencies as the last-resort solve path.
run_mode_four_force_attempt() {
    local lenient_packages=()
    local require_args=()
    local normalized_test_version=""
    local plugin_path=""
    local should_require_test_module=0
    local ai_constraint="$NORMALIZED_AI_VERSION"
    local test_constraint=""
    local module_name=""
    local repo_composer_json=""

    append_lenient_package() {
        local package_name=$1
        local existing=""

        [ -n "$package_name" ] || return 0
        for existing in ${lenient_packages[@]+"${lenient_packages[@]}"}; do
            if [ "$existing" = "$package_name" ]; then
                return 0
            fi
        done
        lenient_packages+=("$package_name")
    }

    add_local_module_dependencies_to_lenient() {
        local module_name=$1
        local repo_composer_json="$PROJECT_ROOT/repos/$module_name/composer.json"
        local root_composer_json="composer.json"
        local dep=""

        [ -f "$repo_composer_json" ] || return 0
        [ -f "$root_composer_json" ] || return 0
        command -v jq >/dev/null 2>&1 || return 0

        while IFS= read -r dep; do
            [ -n "$dep" ] || continue
            # Keep lenient scope narrow: only relax dependencies that are
            # explicitly present in the current root requirements.
            if ! jq -e --arg dep "$dep" '.require[$dep] != null' "$root_composer_json" >/dev/null 2>&1; then
                continue
            fi
            append_lenient_package "$dep"
        done < <(jq -r '.require // {} | keys[] | select(startswith("drupal/"))' "$repo_composer_json")
    }

    if [ "$NORMALIZED_AI_VERSION" != "*" ]; then
        append_lenient_package "drupal/${DP_AI_MODULE}"
    fi
    if [ -n "${DP_AI_ISSUE_BRANCH:-}" ] && [ "$NORMALIZED_AI_VERSION" = "*" ]; then
        ai_constraint="*@dev"
    fi

    normalized_test_version="$(normalize_version_to_composer "${DP_TEST_MODULE_VERSION:-}")"
    test_constraint="$normalized_test_version"
    if [ -n "${DP_TEST_MODULE:-}" ]; then
        if [ "$normalized_test_version" != "*" ] || [ -n "${DP_TEST_MODULE_ISSUE_BRANCH:-}" ]; then
            should_require_test_module=1
        fi
    fi
    if [ -n "${DP_TEST_MODULE_ISSUE_BRANCH:-}" ] && [ "$normalized_test_version" = "*" ]; then
        test_constraint="*@dev"
    fi
    if [ "$should_require_test_module" -eq 1 ]; then
        append_lenient_package "drupal/${DP_TEST_MODULE}"
    fi

    # In forced mode, also relax direct Drupal deps declared by pinned local modules.
    # This keeps force mode targeted while unblocking known ecosystem mismatches.
    if [ -n "${DP_AI_MODULE:-}" ]; then
        add_local_module_dependencies_to_lenient "${DP_AI_MODULE}"
    fi
    if [ "$should_require_test_module" -eq 1 ] && [ -n "${DP_TEST_MODULE:-}" ]; then
        add_local_module_dependencies_to_lenient "${DP_TEST_MODULE}"
    fi

    export DP_FORCE_DEPENDENCIES=1
    export DP_LENIENT_PACKAGES="$(IFS=,; echo "${lenient_packages[*]}")"
    log_info "Enabling lenient mode for explicitly pinned packages: ${lenient_packages[*]}"

    plugin_path="$PROJECT_ROOT/src/ai-lenient-plugin"
    if [ -d "$plugin_path" ]; then
        composer config --no-plugins allow-plugins.drupalpod/ai-lenient-plugin true
        composer config --no-plugins repositories.ai-lenient-plugin \
            "{\"type\": \"path\", \"url\": \"$plugin_path\", \"options\": {\"symlink\": true}}"
        composer require --prefer-dist -n --no-update "drupalpod/ai-lenient-plugin:*@dev"
    fi

    # Keep existing mglaman wiring for compatibility with established workflows.
    configure_lenient_mode ${lenient_packages[@]+"${lenient_packages[@]}"}

    if [ -f composer.lock ]; then
        composer -n update --no-progress \
            mglaman/composer-drupal-lenient \
            drupalpod/ai-lenient-plugin
    else
        composer -n update --no-progress
    fi

    if [ ! -d "vendor/drupalpod/ai-lenient-plugin" ]; then
        log_warn "AI lenient plugin not installed in vendor/"
    fi

    require_args=("drupal/${DP_AI_MODULE}:${ai_constraint}")
    if [ "$should_require_test_module" -eq 1 ]; then
        require_args+=("drupal/${DP_TEST_MODULE}:${test_constraint}")
    fi
    if [ -z "${DP_VERSION:-}" ] && [ "${STARTER_TEMPLATE:-cms}" = "cms" ]; then
        # Force path for CMS auto-detect must still produce a concrete CMS version
        # in composer.lock/manifest. Include drupal/cms so Composer selects a line
        # (latest stable under normal constraints) while lenient rules relax module conflicts.
        require_args+=("drupal/cms")
    fi

    set +e
    COMPOSER_OUT=$(composer require --with-all-dependencies --no-interaction "${require_args[@]}" 2>&1)
    COMPOSER_EXIT=$?
    set -e

    if [ "$COMPOSER_EXIT" -eq 0 ]; then
        COMPATIBILITY="forced"
        PRIMARY_RESOLVED=1
        return
    fi

    CLASSIFICATION=$(classify_composer_failure "$COMPOSER_OUT")
    printf '%s\n' "$COMPOSER_OUT"
    if [ "$COMPOSER_EXIT" -eq 2 ] && [ "$CLASSIFICATION" = "dependency_conflict" ]; then
        write_error_manifest "$MANIFEST_FILE" "4" "error_unresolvable" "$FORCED_REASON" "$FORCED_REASON_LOG" "$STARTER_TEMPLATE" "$DP_VERSION"
    else
        write_error_manifest "$MANIFEST_FILE" "4" "error_infra" "$FORCED_REASON" "$FORCED_REASON_LOG" "$STARTER_TEMPLATE" "$DP_VERSION"
    fi
    exit 1
}
