#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/tuist-common.sh"

readonly DERIVED_DATA_PATH="$MITORI_REPO_ROOT/.xcodebuild/run-macos"
readonly APP_PATH="$DERIVED_DATA_PATH/Build/Products/$MITORI_CONFIGURATION/Mitori.app"
readonly PLIST_PATH="$APP_PATH/Contents/Info.plist"
readonly CLANG_PROBE_WRAPPER_PATH="$MITORI_REPO_ROOT/scripts/clang-probe-wrapper.sh"

wait_for_app_quit() {
  local bundle_id="$1"

  for _ in {1..50}; do
    if ! osascript -e "application id \"$bundle_id\" is running" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done

  return 1
}

ensure_dependencies_installed
ensure_xcode_cache_setup
ensure_external_cache_warmed
ensure_generated_workspace

run_tuist xcodebuild build \
  -workspace "$MITORI_WORKSPACE_PATH" \
  -scheme Mitori \
  -configuration "$MITORI_CONFIGURATION" \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CC="$CLANG_PROBE_WRAPPER_PATH"

if [ ! -f "$PLIST_PATH" ]; then
  echo "Expected Info.plist at $PLIST_PATH" >&2
  exit 1
fi

bundle_id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$PLIST_PATH")

if osascript -e "application id \"$bundle_id\" is running" >/dev/null 2>&1; then
  osascript -e "tell application id \"$bundle_id\" to quit" >/dev/null 2>&1 || true
  wait_for_app_quit "$bundle_id" || true
fi

if osascript -e "application id \"$bundle_id\" is running" >/dev/null 2>&1; then
  pkill -TERM -f "$APP_PATH/Contents/MacOS/" >/dev/null 2>&1 || true
  wait_for_app_quit "$bundle_id" || true
fi

open "$APP_PATH"
