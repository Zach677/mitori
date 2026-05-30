#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        *=*) export "$arg" ;;
        *) echo "Unexpected argument: $arg" >&2; exit 64 ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_OUTPUT="$("$ROOT_DIR/scripts/build-macos.sh" CONFIGURATION="${CONFIGURATION:-debug}")"
printf '%s\n' "$BUILD_OUTPUT"
APP_PATH="$(printf '%s\n' "$BUILD_OUTPUT" | tail -n 1)"

if pgrep -x Mitori >/dev/null 2>&1; then
    pkill -x Mitori || true
    for _ in {1..50}; do
        if ! pgrep -x Mitori >/dev/null 2>&1; then
            break
        fi
        sleep 0.1
    done
fi

open "$APP_PATH"
echo "Launched $APP_PATH"
