#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        *=*) export "${arg?}" ;;
        *) echo "Unexpected argument: $arg" >&2; exit 64 ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-Debug}"
COMMUNITY_BUILD="${COMMUNITY_BUILD:-1}"

case "$CONFIGURATION" in
    debug|Debug)
        CONFIGURATION="Debug"
        OUTPUT_CONFIGURATION="debug"
        ;;
    release|Release)
        CONFIGURATION="Release"
        OUTPUT_CONFIGURATION="release"
        if [[ "$COMMUNITY_BUILD" == "1" ]]; then
            OUTPUT_CONFIGURATION="community"
        fi
        ;;
    *)
        echo "Unsupported CONFIGURATION: $CONFIGURATION" >&2
        exit 64
        ;;
esac

"$ROOT_DIR/scripts/build-macos.sh" \
    CONFIGURATION="$CONFIGURATION" \
    COMMUNITY_BUILD="$COMMUNITY_BUILD"
APP_PATH="$ROOT_DIR/.app-build/$OUTPUT_CONFIGURATION/Mitori.app"

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
