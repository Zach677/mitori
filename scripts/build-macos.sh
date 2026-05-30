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
        CONFIGURATION="debug"
        ;;
    release|Release)
        CONFIGURATION="release"
        ;;
    *)
        echo "Unsupported CONFIGURATION: $CONFIGURATION" >&2
        exit 64
        ;;
esac

cd "$ROOT_DIR"

if [[ "$CONFIGURATION" == "release" ]]; then
    swift build -c release
    EXECUTABLE_PATH="$(swift build -c release --show-bin-path)/$PRODUCT_NAME"
else
    swift build
    EXECUTABLE_PATH="$(swift build --show-bin-path)/$PRODUCT_NAME"
fi

APP_ROOT="$ROOT_DIR/.app-build/$CONFIGURATION/$PRODUCT_NAME.app"
CONTENTS_DIR="$APP_ROOT/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_ROOT"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$PRODUCT_NAME"
chmod +x "$MACOS_DIR/$PRODUCT_NAME"
cp "$ROOT_DIR/Mitori/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"

RESOURCE_BUNDLE="$(dirname "$EXECUTABLE_PATH")/${PRODUCT_NAME}_${PRODUCT_NAME}.bundle"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
    cp -R "$RESOURCE_BUNDLE" "$RESOURCES_DIR/"
fi

echo "$APP_ROOT"
