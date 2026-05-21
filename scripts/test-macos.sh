#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/tuist-common.sh"

readonly DERIVED_DATA_PATH="$MITORI_REPO_ROOT/.xcodebuild/test-macos"
readonly RESULT_BUNDLE_PATH="$DERIVED_DATA_PATH/TestResults/MitoriTests.xcresult"
readonly CLANG_PROBE_WRAPPER_PATH="$MITORI_REPO_ROOT/scripts/clang-probe-wrapper.sh"

ensure_dependencies_installed
ensure_xcode_cache_setup
ensure_external_cache_warmed
ensure_generated_workspace

mkdir -p "$(dirname "$RESULT_BUNDLE_PATH")"
rm -rf "$RESULT_BUNDLE_PATH"

run_tuist test MitoriTests \
  --path "$MITORI_REPO_ROOT" \
  --configuration "$MITORI_CONFIGURATION" \
  -T "$RESULT_BUNDLE_PATH" \
  -- \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  CC="$CLANG_PROBE_WRAPPER_PATH" \
  "$@"
