#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IOS_ROOT="$WORKSPACE_ROOT/apps/ios"
ARTIFACTS_ROOT="${ASTERION_ARTIFACTS_PATH:-$WORKSPACE_ROOT/.artifacts/ios}"
PROJECT_PATH="$IOS_ROOT/Asterion.xcodeproj"
SCHEME="Asterion"
DEVICE_ID="${ASTERION_DEVICE_ID:-00008150-00110911366A401C}"
BUNDLE_ID="cyberverse.Asterion"
DERIVED_DATA_PATH="${ASTERION_DERIVED_DATA_PATH:-$ARTIFACTS_ROOT/device}"
APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Debug-iphoneos/Asterion.app"

mkdir -p "$ARTIFACTS_ROOT"

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
