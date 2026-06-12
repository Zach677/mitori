#!/usr/bin/env bash
set -euo pipefail

for arg in "$@"; do
    case "$arg" in
        *=*) export "$arg" ;;
        *) echo "Unexpected argument: $arg" >&2; exit 64 ;;
    esac
done

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
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

cd "$ROOT_DIR"

xcodebuild \
    -project "$PRODUCT_NAME.xcodeproj" \
    -scheme "$PRODUCT_NAME" \
    -configuration "$CONFIGURATION" \
    -derivedDataPath .xcodebuild \
    -quiet \
    build

BUILT_APP="$ROOT_DIR/.xcodebuild/Build/Products/$CONFIGURATION/$PRODUCT_NAME.app"
OUTPUT_CONFIGURATION="$(printf '%s' "$CONFIGURATION" | tr '[:upper:]' '[:lower:]')"
APP_ROOT="$ROOT_DIR/.app-build/$OUTPUT_CONFIGURATION/$PRODUCT_NAME.app"

rm -rf "$APP_ROOT"
mkdir -p "$(dirname "$APP_ROOT")"
cp -R "$BUILT_APP" "$APP_ROOT"

echo "$APP_ROOT"
