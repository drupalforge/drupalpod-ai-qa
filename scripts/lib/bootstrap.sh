#!/usr/bin/env bash
# Shared bootstrap for scripts that need common utilities/environment.

bootstrap_common() {
    # Idempotent bootstrap so sourced scripts can call this safely more than once.
    if [ "${COMMON_BOOTSTRAPPED:-0}" = "1" ]; then
        return 0
    fi

    if [ -z "${SCRIPT_DIR:-}" ]; then
        local caller_script="${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}"
        export SCRIPT_DIR="$(cd "$(dirname "$caller_script")" && pwd)"
    fi

    source "$SCRIPT_DIR/lib/common.sh"
    init_common
    export COMMON_BOOTSTRAPPED=1
}

bootstrap_common
