#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IOS_ROOT="$WORKSPACE_ROOT/apps/ios"
ARTIFACTS_ROOT="${ASTERION_ARTIFACTS_PATH:-$WORKSPACE_ROOT/.artifacts/ios}"
PROJECT_PATH="$IOS_ROOT/Asterion.xcodeproj"
SCHEME="Asterion"
DEVICE_ID="${ASTERION_DEVICE_ID:-00008150-00110911366A401C}"
DERIVED_DATA_PATH="${ASTERION_DERIVED_DATA_PATH:-$ARTIFACTS_ROOT/device}"
CONFIG="${ASTERION_CONFIG:-Debug}"
IPA_PATH="${ASTERION_IPA_PATH:-$ARTIFACTS_ROOT/Asterion-existing-build.ipa}"
PACKAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/asterion-existing-build.XXXXXX")"

cleanup() {
  rm -rf "$PACKAGE_ROOT"
}
trap cleanup EXIT

mkdir -p "$ARTIFACTS_ROOT"

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

mkdir -p "$PACKAGE_ROOT/Payload"
cp -R "${APP_PATH}" "$PACKAGE_ROOT/Payload/"
(
  cd "$PACKAGE_ROOT"
  zip -rq "${IPA_PATH}" Payload
)

echo "==> IPA ready: ${IPA_PATH}"
