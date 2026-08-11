#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 || ! -f "$1" ]]; then
    echo "Usage: $0 <community-dmg-path>" >&2
    exit 1
fi
DMG_PATH="$(cd "$(dirname "$1")" && pwd -P)/$(basename "$1")"
MOUNT_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mitori-smoke.XXXXXX")"
MOUNT_DIR="$(cd "$MOUNT_DIR" && pwd -P)"
APP_PATH="$MOUNT_DIR/Mitori.app"
APP_PID=""
IS_MOUNTED=false

# Invoked by the EXIT trap.
# shellcheck disable=SC2329
cleanup() {
    local status=$?
    trap - EXIT
    set +e

    if [[ ! "$APP_PID" =~ ^[0-9]+$ ]]; then
        local app_asn
        local app_info
        app_asn="$(lsappinfo find "bundlepath=$APP_PATH" 2>/dev/null || true)"
        app_info="$(lsappinfo info -long -app "$app_asn" 2>/dev/null || true)"
        APP_PID="$(sed -n 's/^"pid"=//p' <<<"$app_info")"
    fi
    if [[ "$APP_PID" =~ ^[0-9]+$ ]] && kill -0 "$APP_PID" 2>/dev/null; then
        kill -TERM "$APP_PID" 2>/dev/null
        local quit_deadline=$((SECONDS + 5))
        while kill -0 "$APP_PID" 2>/dev/null && (( SECONDS < quit_deadline )); do
            sleep 0.1
        done
        if kill -0 "$APP_PID" 2>/dev/null; then
            kill -KILL "$APP_PID" 2>/dev/null
        fi
    fi

    if [[ "$IS_MOUNTED" == true ]]; then
        local detach_deadline=$((SECONDS + 5))
        while (( SECONDS < detach_deadline )); do
            if hdiutil detach "$MOUNT_DIR" -quiet 2>/dev/null; then
                IS_MOUNTED=false
                break
            fi
            sleep 0.25
        done
        if [[ "$IS_MOUNTED" == true ]]; then
            echo "Failed to detach smoke-test DMG at $MOUNT_DIR." >&2
            status=1
        fi
    fi
    rmdir "$MOUNT_DIR" 2>/dev/null || true
    exit "$status"
}
trap cleanup EXIT

hdiutil attach "$DMG_PATH" -nobrowse -readonly -mountpoint "$MOUNT_DIR" -quiet
IS_MOUNTED=true

if [[ ! -x "$APP_PATH/Contents/MacOS/Mitori" ]]; then
    echo "Mounted DMG does not contain an executable Mitori.app." >&2
    exit 1
fi

open -n "$APP_PATH"
launch_deadline=$((SECONDS + 20))
while (( SECONDS < launch_deadline )); do
    APP_ASN="$(lsappinfo find "bundlepath=$APP_PATH" 2>/dev/null || true)"
    if [[ -n "$APP_ASN" ]]; then
        APP_INFO="$(lsappinfo info -long -app "$APP_ASN" 2>/dev/null || true)"
        APP_PID="$(sed -n 's/^"pid"=//p' <<<"$APP_INFO")"
        if grep -q '^"LSApplicationHasSignalledItIsReady"=true$' <<<"$APP_INFO"; then
            echo "Packaged Mitori.app signalled launch readiness (pid $APP_PID)."
            exit 0
        fi
    fi
    sleep 0.25
done

echo "Packaged Mitori.app did not signal launch readiness within 20 seconds." >&2
exit 1
