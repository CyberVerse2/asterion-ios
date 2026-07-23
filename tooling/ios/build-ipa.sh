#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IOS_ROOT="$WORKSPACE_ROOT/apps/ios"
ARTIFACTS_ROOT="${ASTERION_ARTIFACTS_PATH:-$WORKSPACE_ROOT/.artifacts/ios}"
PROJECT_PATH="$IOS_ROOT/Asterion.xcodeproj"
SCHEME="Asterion"
CONFIG="${ASTERION_CONFIG:-Debug}"
ARCHIVE_PATH="$ARTIFACTS_ROOT/Asterion.xcarchive"
IPA_PATH="${ASTERION_IPA_PATH:-$ARTIFACTS_ROOT/Asterion.ipa}"
EXPORT_PATH="$ARTIFACTS_ROOT/export"
EXPORT_PLIST="$ARTIFACTS_ROOT/exportOptions.plist"

mkdir -p "$ARTIFACTS_ROOT"

echo "==> Archiving Asterion (${CONFIG})..."

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -archivePath "${ARCHIVE_PATH}" \
  -allowProvisioningUpdates \
  archive

cat > "${EXPORT_PLIST}" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>development</string>
    <key>teamID</key>
    <string>V6Y7WXX6Z5</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>stripSwiftSymbols</key>
    <true/>
</dict>
</plist>
PLIST

echo "==> Exporting IPA..."

xcodebuild \
  -exportArchive \
  -archivePath "${ARCHIVE_PATH}" \
  -exportPath "${EXPORT_PATH}" \
  -exportOptionsPlist "${EXPORT_PLIST}" \
  -allowProvisioningUpdates

mv "${EXPORT_PATH}/Asterion.ipa" "${IPA_PATH}"

rm -rf "${ARCHIVE_PATH}" "${EXPORT_PATH}" "${EXPORT_PLIST}"

echo "==> IPA ready: ${IPA_PATH}"
echo "    Open in SideStore to install."
