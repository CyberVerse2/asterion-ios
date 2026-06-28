#!/usr/bin/env bash
set -euo pipefail

PROJECT_PATH="Asterion.xcodeproj"
SCHEME="Asterion"
CONFIG="${ASTERION_CONFIG:-Release}"
DERIVED_DATA_PATH=".build/trollstore-ipa"
IPA_NAME="${ASTERION_IPA_NAME:-Asterion.ipa}"

echo "==> Building unsigned IPA for TrollStore (${CONFIG})..."

xcodebuild \
  -project "${PROJECT_PATH}" \
  -scheme "${SCHEME}" \
  -configuration "${CONFIG}" \
  -sdk iphoneos \
  -destination "generic/platform=iOS" \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/${CONFIG}-iphoneos/Asterion.app"

rm -rf Payload
mkdir -p Payload
cp -R "${APP_PATH}" Payload/
zip -rq "${IPA_NAME}" Payload
rm -rf Payload

echo "==> IPA ready: ${IPA_NAME}"
echo "    AirDrop it to your device and open with TrollStore, or"
echo "    serve with:  python3 -m http.server 8080"
