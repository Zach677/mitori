#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/tuist-common.sh"

readonly DERIVED_DATA_PATH="$MITORI_REPO_ROOT/.xcodebuild/test-macos"

ensure_dependencies_installed
ensure_external_cache_warmed
ensure_generated_workspace

/usr/bin/xcodebuild test \
  -workspace "$MITORI_WORKSPACE_PATH" \
  -scheme MitoriTests \
  -configuration "$MITORI_CONFIGURATION" \
  -destination 'platform=macOS' \
  -derivedDataPath "$DERIVED_DATA_PATH" \
  CODE_SIGNING_ALLOWED=NO \
  "$@"
