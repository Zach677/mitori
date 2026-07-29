#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        *=*) export "${arg?}" ;;
        *) echo "Unexpected argument: $arg" >&2; exit 64 ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COMMUNITY_BUILD="${COMMUNITY_BUILD:-1}"
DERIVED_DATA_PATH=".xcodebuild"
if [[ "$COMMUNITY_BUILD" == "1" ]]; then
    DERIVED_DATA_PATH=".xcodebuild/community"
fi

XCODEBUILD_ARGUMENTS=(
    -project Mitori.xcodeproj
    -scheme Mitori
    -destination "platform=macOS"
    -derivedDataPath "$DERIVED_DATA_PATH"
    -parallel-testing-enabled NO
)
if [[ "$COMMUNITY_BUILD" == "1" ]]; then
    XCODEBUILD_ARGUMENTS+=(
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) MITORI_COMMUNITY_BUILD"
        CODE_SIGN_ENTITLEMENTS=
        CODE_SIGN_IDENTITY=-
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
