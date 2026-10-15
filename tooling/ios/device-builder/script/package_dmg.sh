#!/usr/bin/env bash
set -euo pipefail

APP_NAME="Asterion Device"
EXECUTABLE_NAME="AsterionDevice"
BUNDLE_ID="cloud.cyberverse.AsterionDevice"
MIN_SYSTEM_VERSION="26.0"
APP_VERSION="${ASTERION_DEVICE_VERSION:-0.1.0}"
BUILD_NUMBER="${ASTERION_DEVICE_BUILD_NUMBER:-1}"
CODE_SIGN_IDENTITY="${ASTERION_CODE_SIGN_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$EXECUTABLE_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"
DMG_STAGING="$DIST_DIR/.dmg-staging"
DMG_MOUNT="$DIST_DIR/.dmg-mount"
DMG_ATTACHED=false

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning \
      | /usr/bin/sed -En 's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) ".*"$/\1/p' \
      | /usr/bin/sed -n '1p'
  )"
fi

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  echo "error: no valid Apple code-signing identity is available" >&2
  echo "Install an Apple Development certificate or set ASTERION_CODE_SIGN_IDENTITY." >&2
  exit 1
fi

cd "$ROOT_DIR"
swift build -c release --product "$EXECUTABLE_NAME"
BIN_DIR="$(swift build -c release --show-bin-path)"
BUILD_BINARY="$BIN_DIR/$EXECUTABLE_NAME"

mkdir -p "$DIST_DIR"

cleanup() {
  if [[ "$DMG_ATTACHED" == true ]]; then
    /usr/bin/hdiutil detach "$DMG_MOUNT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$DMG_STAGING" "$DMG_MOUNT"
}
trap cleanup EXIT

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$EXECUTABLE_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleDisplayName</key>
  <string>$APP_NAME</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

# Unsigned SwiftPM helper that shells out to xcodebuild / devicectl.
# Sign for Gatekeeper on this Mac, but do not sandbox or enable hardened runtime.
/usr/bin/codesign \
  --force \
  --timestamp=none \
  --sign "$CODE_SIGN_IDENTITY" \
  --identifier "$BUNDLE_ID" \
  "$APP_BUNDLE"

/usr/bin/codesign \
  --verify \
  --deep \
  --strict \
  -R="identifier \"$BUNDLE_ID\" and anchor apple generic" \
  "$APP_BUNDLE"

rm -rf "$DMG_STAGING" "$DMG_MOUNT"
rm -f "$DMG_PATH" "$DMG_CHECKSUM_PATH"
mkdir -p "$DMG_STAGING" "$DMG_MOUNT"
cp -R "$APP_BUNDLE" "$DMG_STAGING/$APP_NAME.app"
ln -s /Applications "$DMG_STAGING/Applications"

/usr/bin/hdiutil create \
  -volname "$APP_NAME" \
  -srcfolder "$DMG_STAGING" \
  -format UDZO \
  -imagekey zlib-level=9 \
  -ov \
  "$DMG_PATH"

/usr/bin/codesign \
  --force \
  --timestamp=none \
  --sign "$CODE_SIGN_IDENTITY" \
  "$DMG_PATH"
/usr/bin/codesign --verify --verbose=2 "$DMG_PATH"
/usr/bin/hdiutil verify "$DMG_PATH"

/usr/bin/hdiutil attach \
  -mountpoint "$DMG_MOUNT" \
  -nobrowse \
  -readonly \
  "$DMG_PATH" >/dev/null
DMG_ATTACHED=true

[[ -d "$DMG_MOUNT/$APP_NAME.app" ]]
[[ -L "$DMG_MOUNT/Applications" ]]
[[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DMG_MOUNT/$APP_NAME.app/Contents/Info.plist")" == "$BUNDLE_ID" ]]
/usr/bin/codesign \
  --verify \
  --deep \
  --strict \
  -R="identifier \"$BUNDLE_ID\" and anchor apple generic" \
  "$DMG_MOUNT/$APP_NAME.app"

/usr/bin/hdiutil detach "$DMG_MOUNT" >/dev/null
DMG_ATTACHED=false
/usr/bin/shasum -a 256 "$DMG_PATH" >"$DMG_CHECKSUM_PATH"

echo "DMG: $DMG_PATH"
echo "SHA-256: $DMG_CHECKSUM_PATH"
