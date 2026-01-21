#!/usr/bin/env bash
set -eu -o pipefail

# Thin wrapper to keep DevPanel script location.
# All the build scripts are in the "scripts" directory,
# so ddev and other tools can find them easily and it
# makes more sense for shared usage.
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/../scripts/init.sh"
