#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Asterion"
BUNDLE_ID="cloud.cyberverse.Asterion"
MIN_SYSTEM_VERSION="15.0"
CODE_SIGN_IDENTITY="${ASTERION_CODE_SIGN_IDENTITY:-}"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"

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

pkill -x "$APP_NAME" >/dev/null 2>&1 || true
pkill -x "AsterionMac" >/dev/null 2>&1 || true

cd "$ROOT_DIR"
swift build
BIN_DIR="$(swift build --show-bin-path)"
BUILD_BINARY="$BIN_DIR/$APP_NAME"
mkdir -p "$DIST_DIR"
SIGNED_BINARY="$(/usr/bin/mktemp "$DIST_DIR/.${APP_NAME}.XXXXXX")"
trap 'rm -f "$SIGNED_BINARY"' EXIT

cp "$BUILD_BINARY" "$SIGNED_BINARY"
chmod +x "$SIGNED_BINARY"

/usr/bin/codesign \
  --force \
  --sign "$CODE_SIGN_IDENTITY" \
  --identifier "$BUNDLE_ID" \
  "$SIGNED_BINARY"

/usr/bin/codesign \
  --verify \
  --strict \
  -R="identifier \"$BUNDLE_ID\" and anchor apple generic" \
  "$SIGNED_BINARY"

rm -rf "$APP_BUNDLE" "$DIST_DIR/AsterionMac.app"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
mv "$SIGNED_BINARY" "$APP_BINARY"

find "$BIN_DIR" -maxdepth 1 -type d -name '*.bundle' -exec cp -R {} "$APP_BUNDLE/" \;

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
done < <(find "$APP_BUNDLE" -maxdepth 1 -type d -name '*.bundle' -print0)

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
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
