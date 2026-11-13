#!/usr/bin/env bash
# Make a release on the maintainer's Mac: archive, sign with Developer ID, notarize,
# staple, and pack a DMG in dist/.
# Needs a Developer ID Application certificate in the Keychain and the notarytool
# keychain profile "mitori-notary" (xcrun notarytool store-credentials).
# PUBLISH=1 also creates the GitHub release. The tag v<version> must be on HEAD and on the remote.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEAM_ID="2R495YX57L"
NOTARY_PROFILE="mitori-notary"
PUBLISH="${PUBLISH:-0}"
ARCHIVE_PATH="$ROOT_DIR/.xcodebuild/Mitori.xcarchive"
EXPORT_DIR="$ROOT_DIR/.app-build/release"
APP_PATH="$EXPORT_DIR/Mitori.app"
DIST_DIR="$ROOT_DIR/dist"

fail() { echo "$1" >&2; exit 1; }

# notarytool can exit 0 for a rejected upload. The staple step that follows fails when there is no ticket.
notarize() { xcrun notarytool submit "$1" --keychain-profile "$NOTARY_PROFILE" --wait; }

# When Gatekeeper is disabled on this Mac, spctl accepts everything. The source line stays accurate.
assess() {
    local output
    output="$(spctl --assess --verbose=2 "$@" 2>&1)" || true
    echo "$output"
    [[ "$output" == *"source=Notarized Developer ID"* ]] || fail "Gatekeeper does not see a notarized Developer ID signature."
}

cd "$ROOT_DIR"

command -v xcbeautify >/dev/null 2>&1 || { echo "xcbeautify is required" >&2; exit 69; }
if [[ "$PUBLISH" == 1 ]]; then
    command -v gh >/dev/null 2>&1 || { echo "gh is required" >&2; exit 69; }
    [[ -z "$(git status --porcelain)" ]] \
        || fail "The working tree is not clean. Commit or remove the changes before a release."
fi

WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/mitori-release.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

# The prefix map keeps the path of this checkout out of the Objective-C objects.
xcodebuild \
    -project Mitori.xcodeproj \
    -scheme Mitori \
    -configuration Release \
    -derivedDataPath .xcodebuild \
    -archivePath "$ARCHIVE_PATH" \
    "OTHER_CFLAGS=\$(inherited) -fmacro-prefix-map=$ROOT_DIR=." \
    archive | xcbeautify --disable-colored-output --disable-logging

cat > "$WORK_DIR/ExportOptions.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>developer-id</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>$TEAM_ID</string>
</dict>
</plist>
EOF

# The Keychain entitlement needs a Developer ID provisioning profile.
# The first export makes that profile in the Apple developer account.
rm -rf "$EXPORT_DIR"
xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_DIR" \
    -exportOptionsPlist "$WORK_DIR/ExportOptions.plist" \
    -allowProvisioningUpdates

codesign --verify --deep --strict "$APP_PATH"
SIGNATURE="$(codesign -d --verbose=4 "$APP_PATH" 2>&1)"
[[ "$SIGNATURE" == *"Authority=Developer ID Application:"* ]] || fail "The app is not signed with Developer ID."
[[ "$SIGNATURE" == *"TeamIdentifier=$TEAM_ID"* ]] || fail "The app is not signed by team $TEAM_ID."
[[ "$SIGNATURE" == *"(runtime)"* ]] || fail "The app does not use the Hardened Runtime."
ENTITLEMENTS="$(codesign -d --entitlements - "$APP_PATH" 2>/dev/null)"
[[ "$ENTITLEMENTS" == *"$TEAM_ID.dev.zach.mitori"* ]] || fail "The app has no Keychain access group."
[[ "$ENTITLEMENTS" != *"get-task-allow"* ]] || fail "The app has the get-task-allow entitlement."
[[ -f "$APP_PATH/Contents/embedded.provisionprofile" ]] || fail "The app has no provisioning profile."
for arch in arm64 x86_64; do
    lipo "$APP_PATH/Contents/MacOS/Mitori" -verify_arch "$arch" || fail "The app has no $arch slice."
done
if LC_ALL=C grep -aERq '/Users/[^/]+/' "$APP_PATH"; then
    fail "The app contains an absolute user path."
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP_PATH/Contents/Info.plist")"
if [[ "$PUBLISH" == 1 ]]; then
    [[ "$(git rev-parse HEAD)" == "$(git rev-parse "v$VERSION^{commit}" 2>/dev/null)" ]] \
        || fail "The tag v$VERSION is not on HEAD."
fi

ditto -c -k --keepParent "$APP_PATH" "$WORK_DIR/Mitori.zip"
notarize "$WORK_DIR/Mitori.zip"
xcrun stapler staple "$APP_PATH"

DMG_NAME="Mitori-$VERSION.dmg"
DMG_PATH="$DIST_DIR/$DMG_NAME"
mkdir -p "$DIST_DIR" "$WORK_DIR/dmg"
rm -f "$DMG_PATH" "$DMG_PATH.sha256"
cp -R "$APP_PATH" "$WORK_DIR/dmg/Mitori.app"
ln -s /Applications "$WORK_DIR/dmg/Applications"
cp LICENSE "$WORK_DIR/dmg/LICENSE"
diskutil image create from \
    --volumeName Mitori \
    --format UDZO \
    "$WORK_DIR/dmg" \
    "$DMG_PATH"
codesign --sign "Developer ID Application" --timestamp "$DMG_PATH"
notarize "$DMG_PATH"
xcrun stapler staple "$DMG_PATH"

xcrun stapler validate "$APP_PATH"
xcrun stapler validate "$DMG_PATH"
assess --type execute "$APP_PATH"
assess --type open --context context:primary-signature "$DMG_PATH"
hdiutil verify "$DMG_PATH"
(
    cd "$DIST_DIR"
    shasum -a 256 "$DMG_NAME" > "$DMG_NAME.sha256"
)

if [[ "$PUBLISH" == 1 ]]; then
    gh release create "v$VERSION" "$DMG_PATH" "$DMG_PATH.sha256" --generate-notes --verify-tag
    # shortcut: the Homebrew cask is updated by hand, automate it when releases are frequent.
    echo "Update the Homebrew cask: version $VERSION, sha256 $(cut -d ' ' -f 1 "$DMG_PATH.sha256")"
fi

echo "$DMG_PATH"
