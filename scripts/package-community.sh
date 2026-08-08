#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="$ROOT_DIR/.app-build/community/Mitori.app"
DIST_DIR="$ROOT_DIR/dist"

cd "$ROOT_DIR"
zsh scripts/scan.license.sh
COMMUNITY_BUILD=1 CONFIGURATION=Release bash scripts/build-macos.sh

codesign --force --sign - --options runtime "$APP_PATH"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"

if LC_ALL=C grep -aERq '/Users/[^/]+/' "$APP_PATH"; then
    echo "Community app contains an absolute user path." >&2
    exit 1
fi

if otool -l "$APP_PATH/Contents/MacOS/Mitori" | grep '__llvm_prf' >/dev/null; then
    echo "Community binary contains coverage instrumentation." >&2
    exit 1
fi

if [[ -f "$APP_PATH/Contents/embedded.provisionprofile" ]]; then
    echo "Community app unexpectedly contains a provisioning profile." >&2
    exit 1
fi

ENTITLEMENTS="$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null)"
if [[ -n "$ENTITLEMENTS" ]]; then
    echo "Community app unexpectedly contains signed entitlements." >&2
    exit 1
fi

SIGNATURE_DETAILS="$(codesign -d --verbose=4 "$APP_PATH" 2>&1)"
if [[ "$SIGNATURE_DETAILS" != *"Signature=adhoc"* || "$SIGNATURE_DETAILS" != *"runtime"* ]]; then
    echo "Community app is not ad hoc signed with Hardened Runtime." >&2
    exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ "${GITHUB_REF_NAME:-}" == v* && "${GITHUB_REF_NAME#v}" != "$VERSION" ]]; then
    echo "Tag ${GITHUB_REF_NAME} does not match app version $VERSION." >&2
    exit 1
fi
DMG_NAME="Mitori-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
STAGING_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mitori-dmg.XXXXXX")"
trap 'rm -rf "$STAGING_DIR"' EXIT

mkdir -p "$DIST_DIR"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
cp -R "$APP_PATH" "$STAGING_DIR/Mitori.app"
ln -s /Applications "$STAGING_DIR/Applications"
cp LICENSE "$STAGING_DIR/LICENSE"

diskutil image create from \
    --volumeName Mitori \
    --format UDZO \
    "$STAGING_DIR" \
    "$DMG_PATH"
hdiutil verify "$DMG_PATH"
(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

echo "$DMG_PATH"
