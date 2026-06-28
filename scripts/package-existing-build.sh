#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="Asterion.xcodeproj"
SCHEME="Asterion"
DEVICE_ID="${ASTERION_DEVICE_ID:-00008150-00110911366A401C}"
DERIVED_DATA_PATH="${ASTERION_DERIVED_DATA_PATH:-.build/ios-device}"
CONFIG="${ASTERION_CONFIG:-Debug}"
IPA_NAME="Asterion.ipa"

echo "==> Building for device ${DEVICE_ID} (${CONFIG})..."

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -destination "id=${DEVICE_ID}" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  -allowProvisioningUpdates \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIG}-iphoneos/Asterion.app"

echo "==> Packaging IPA..."

rm -rf Payload
mkdir -p Payload
cp -R "${APP_PATH}" Payload/
zip -rq "${IPA_NAME}" Payload
rm -rf Payload

echo "==> IPA ready: ${IPA_NAME}"
