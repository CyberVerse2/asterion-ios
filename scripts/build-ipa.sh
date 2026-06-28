#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="Asterion.xcodeproj"
SCHEME="Asterion"
CONFIG="${ASTERION_CONFIG:-Debug}"
ARCHIVE_PATH=".build/Asterion.xcarchive"
IPA_NAME="${ASTERION_IPA_NAME:-Asterion.ipa}"
EXPORT_PLIST=".build/exportOptions.plist"

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
  -exportPath ".build" \
  -exportOptionsPlist "${EXPORT_PLIST}" \
  -allowProvisioningUpdates

mv ".build/Asterion.ipa" "${IPA_NAME}"

rm -rf "${ARCHIVE_PATH}" "${EXPORT_PLIST}"

echo "==> IPA ready: ${IPA_NAME}"
echo "    Open in SideStore to install."
