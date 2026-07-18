#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Asterion"
BUNDLE_ID="cloud.cyberverse.Asterion"
MIN_SYSTEM_VERSION="26.0"
APP_VERSION="${ASTERION_VERSION:-0.1.0}"
BUILD_NUMBER="${ASTERION_BUILD_NUMBER:-1}"
CODE_SIGN_IDENTITY="${ASTERION_CODE_SIGN_IDENTITY:-}"
CLERK_PUBLISHABLE_KEY="${ASTERION_CLERK_PUBLISHABLE_KEY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
DMG_PATH="$DIST_DIR/$APP_NAME.dmg"
DMG_CHECKSUM_PATH="$DMG_PATH.sha256"
DMG_STAGING="$DIST_DIR/.dmg-staging"
DMG_MOUNT="$DIST_DIR/.dmg-mount"
DMG_ATTACHED=false

BUILD_CONFIGURATION="debug"
if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  BUILD_CONFIGURATION="release"
fi

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  CODE_SIGN_IDENTITY="$(
    /usr/bin/security find-identity -v -p codesigning \
      | /usr/bin/sed -En 's/^[[:space:]]*[0-9]+\) ([0-9A-F]{40}) ".*"$/\1/p' \
      | /usr/bin/sed -n '1p'
  )"
fi

if [[ "$MODE" == "--package" || "$MODE" == "package" ]]; then
  if [[ "$CLERK_PUBLISHABLE_KEY" != pk_live_* ]]; then
    echo "error: ASTERION_CLERK_PUBLISHABLE_KEY must contain a production Clerk publishable key" >&2
    exit 1
  fi

  if ! /usr/bin/security find-identity -v -p codesigning \
    | /usr/bin/grep -F "$CODE_SIGN_IDENTITY" \
    | /usr/bin/grep -q '"Developer ID Application:'; then
    echo "warning: no Developer ID Application identity is selected" >&2
    echo "warning: the DMG will be development-signed and cannot be notarized for public distribution" >&2
  fi
fi

if [[ -z "$CODE_SIGN_IDENTITY" ]]; then
  echo "error: no valid Apple code-signing identity is available" >&2
  echo "Install an Apple Development certificate or set ASTERION_CODE_SIGN_IDENTITY." >&2
  exit 1
fi

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "AsterionMac" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build -c "$BUILD_CONFIGURATION"
BIN_DIR="$(swift build -c "$BUILD_CONFIGURATION" --show-bin-path)"

# SwiftPM's command-line resource accessors look beside the executable. Inside
# a macOS app bundle, signed resources belong in Contents/Resources instead.
# Rebuild the affected modules with accessors that support both layouts.
while IFS= read -r -d '' RESOURCE_ACCESSOR; do
  /usr/bin/perl -pi -e \
    's/Bundle\.main\.bundleURL\.appendingPathComponent/\(Bundle.main.resourceURL ?? Bundle.main.bundleURL\).appendingPathComponent/g' \
    "$RESOURCE_ACCESSOR"
done < <(/usr/bin/find "$BIN_DIR" -path '*/DerivedSources/resource_bundle_accessor.swift' -print0)
swift build -c "$BUILD_CONFIGURATION"

BUILD_BINARY="$BIN_DIR/$APP_NAME"
mkdir -p "$DIST_DIR"

cleanup() {
  if [[ "$DMG_ATTACHED" == true ]]; then
    /usr/bin/hdiutil detach "$DMG_MOUNT" -force >/dev/null 2>&1 || true
  fi
  rm -rf "$DMG_STAGING" "$DMG_MOUNT"
}
trap cleanup EXIT

rm -rf "$APP_BUNDLE" "$DIST_DIR/AsterionMac.app"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"

find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "$APP_RESOURCES/" \;

while IFS= read -r -d '' RESOURCE_BUNDLE; do
  ASSET_CATALOGS=()
  while IFS= read -r -d '' ASSET_CATALOG; do
    ASSET_CATALOGS+=("$ASSET_CATALOG")
  done < <(find "$RESOURCE_BUNDLE" -maxdepth 1 -type d -name '*.xcassets' -print0)

  if (( ${#ASSET_CATALOGS[@]} > 0 )); then
    PARTIAL_PLIST="$(/usr/bin/mktemp "$DIST_DIR/.asset-info.XXXXXX")"
    /usr/bin/xcrun actool \
      --compile "$RESOURCE_BUNDLE" \
      --platform macosx \
      --minimum-deployment-target "$MIN_SYSTEM_VERSION" \
      --output-partial-info-plist "$PARTIAL_PLIST" \
      "${ASSET_CATALOGS[@]}"
    rm -rf "${ASSET_CATALOGS[@]}" "$PARTIAL_PLIST"
  fi
done < <(find "$APP_RESOURCES" -maxdepth 1 -type d -name '*.bundle' -print0)

if [[ -f "$ROOT_DIR/Resources/AppIcon.icns" ]]; then
  cp "$ROOT_DIR/Resources/AppIcon.icns" "$APP_RESOURCES/AppIcon.icns"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>Asterion</string>
  <key>CFBundleDisplayName</key>
  <string>Asterion</string>
  <key>CFBundleShortVersionString</key>
  <string>$APP_VERSION</string>
  <key>CFBundleVersion</key>
  <string>$BUILD_NUMBER</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
  <key>NSHighResolutionCapable</key>
  <true/>
</dict>
</plist>
PLIST

if [[ -n "$CLERK_PUBLISHABLE_KEY" ]]; then
  /usr/libexec/PlistBuddy \
    -c "Add :AsterionClerkPublishableKey string $CLERK_PUBLISHABLE_KEY" \
    "$INFO_PLIST"
fi

/usr/bin/codesign \
  --force \
  --timestamp=none \
  --options runtime \
  --sign "$CODE_SIGN_IDENTITY" \
  --identifier "$BUNDLE_ID" \
  "$APP_BUNDLE"

/usr/bin/codesign \
  --verify \
  --deep \
  --strict \
  -R="identifier \"$BUNDLE_ID\" and anchor apple generic" \
  "$APP_BUNDLE"

package_dmg() {
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
}

open_app() {
  /usr/bin/open -n "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    open_app
    sleep 2
    pgrep -x "$APP_NAME" >/dev/null
    ;;
  --package|package)
    package_dmg
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify|--package]" >&2
    exit 2
    ;;
esac
