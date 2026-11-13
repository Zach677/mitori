#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        *=*) export "${arg?}" ;;
        *) echo "Unexpected argument: $arg" >&2; exit 64 ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DERIVED_DATA_PATH=".xcodebuild"

XCODEBUILD_ARGUMENTS=(
    -project Mitori.xcodeproj
    -scheme Mitori
    -destination "platform=macOS"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -parallel-testing-enabled NO
    -only-testing:"${TEST_TARGET:-MitoriTests}"
)
if [[ "${TEST_TARGET:-}" == MitoriUITests* ]]; then
    # Synthesized UI events sometimes time out while the app is idle; retry once
    # instead of adding sleeps. A retried test still shows in the result bundle.
    XCODEBUILD_ARGUMENTS+=(-retry-tests-on-failure -test-iterations 2)
fi
if [[ -n "${CI:-}" ]]; then
    # CI runners have no team certificate, so sign to run locally without entitlements.
    XCODEBUILD_ARGUMENTS+=(
        CODE_SIGN_IDENTITY=-
        CODE_SIGN_ENTITLEMENTS=
        CODE_SIGN_STYLE=Manual
        DEVELOPMENT_TEAM=
        PROVISIONING_PROFILE_SPECIFIER=
    )
fi

cd "$ROOT_DIR"

if ! command -v xcbeautify >/dev/null 2>&1; then
    echo "xcbeautify is required. Install it with: brew install xcbeautify" >&2
    exit 69
fi

xcodebuild "${XCODEBUILD_ARGUMENTS[@]}" test | xcbeautify --disable-colored-output --disable-logging
