#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="Asterion.xcodeproj"
SCHEME="Asterion"
DEVICE_ID="00008150-00110911366A401C"
BUNDLE_ID="cyberverse.Asterion"
DERIVED_DATA_PATH=".build/ios-device"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphoneos/Asterion.app"

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -destination "id=${DEVICE_ID}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -allowProvisioningUpdates \
  build

xcrun devicectl device install app \
  --device "${DEVICE_ID}" \
  "${APP_PATH}"

xcrun devicectl device process launch \
  --device "${DEVICE_ID}" \
  "${BUNDLE_ID}"
