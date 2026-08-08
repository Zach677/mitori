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
CONFIGURATION="${CONFIGURATION:-Debug}"
PRODUCT_NAME="Mitori"

case "$CONFIGURATION" in
    debug|Debug)
        CONFIGURATION="Debug"
        ;;
    release|Release)
        CONFIGURATION="Release"
        ;;
    *)
        echo "Unsupported CONFIGURATION: $CONFIGURATION" >&2
        exit 64
        ;;
esac

DERIVED_DATA_PATH=".xcodebuild"
if [[ "$COMMUNITY_BUILD" == "1" ]]; then
    DERIVED_DATA_PATH=".xcodebuild/community"
fi

XCODEBUILD_ARGUMENTS=(
    -project "$PRODUCT_NAME.xcodeproj"
    -scheme "$PRODUCT_NAME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
)
OUTPUT_CONFIGURATION="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"
if [[ "$COMMUNITY_BUILD" == "1" ]]; then
    XCODEBUILD_ARGUMENTS+=(
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS=\$(inherited) MITORI_COMMUNITY_BUILD"
        "OTHER_CFLAGS=\$(inherited) -fmacro-prefix-map=$ROOT_DIR=."
        "OTHER_CPLUSPLUSFLAGS=\$(inherited) -fmacro-prefix-map=$ROOT_DIR=."
        CODE_SIGN_ENTITLEMENTS=
        CODE_SIGN_IDENTITY=-
        CODE_SIGN_INJECT_BASE_ENTITLEMENTS=NO
        CODE_SIGN_STYLE=Manual
        DEVELOPMENT_TEAM=
        PROVISIONING_PROFILE_SPECIFIER=
    )
    if [[ "$CONFIGURATION" == "Release" ]]; then
        XCODEBUILD_ARGUMENTS+=(
            CLANG_ENABLE_CODE_COVERAGE=NO
            COPY_PHASE_STRIP=YES
            DEPLOYMENT_POSTPROCESSING=YES
            ENABLE_CODE_COVERAGE=NO
            ENABLE_HARDENED_RUNTIME=YES
            GCC_GENERATE_TEST_COVERAGE_FILES=NO
            GCC_INSTRUMENT_PROGRAM_FLOW_ARCS=NO
            STRIP_INSTALLED_PRODUCT=YES
            STRIP_SWIFT_SYMBOLS=YES
        )
        OUTPUT_CONFIGURATION="community"
    fi
fi

cd "$ROOT_DIR"

if ! command -v xcbeautify >/dev/null 2>&1; then
    echo "xcbeautify is required. Install it with: brew install xcbeautify" >&2
    exit 69
fi

xcodebuild "${XCODEBUILD_ARGUMENTS[@]}" build | xcbeautify --disable-colored-output --disable-logging

BUILT_APP="$ROOT_DIR/$DERIVED_DATA_PATH/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"
APP_ROOT="$ROOT_DIR/.app-build/$OUTPUT_CONFIGURATION/$PRODUCT_NAME.app"

rm -rf "$APP_ROOT"
mkdir -p "$(dirname "$APP_ROOT")"
cp -R "$BUILT_APP" "$APP_ROOT"

echo "$APP_ROOT"
