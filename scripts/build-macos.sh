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

XCODEBUILD_ARGUMENTS=(
    -project "$PRODUCT_NAME.xcodeproj"
    -scheme "$PRODUCT_NAME"
    -configuration "$CONFIGURATION"
    -derivedDataPath "$DERIVED_DATA_PATH"
)
OUTPUT_CONFIGURATION="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"

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
