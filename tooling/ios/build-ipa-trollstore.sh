#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
IOS_ROOT="$WORKSPACE_ROOT/apps/ios"
ARTIFACTS_ROOT="${ASTERION_ARTIFACTS_PATH:-$WORKSPACE_ROOT/.artifacts/ios}"
PROJECT_PATH="$IOS_ROOT/Asterion.xcodeproj"
SCHEME="Asterion"
CONFIG="${ASTERION_CONFIG:-Release}"
DERIVED_DATA_PATH="$ARTIFACTS_ROOT/trollstore-derived"
IPA_PATH="${ASTERION_IPA_PATH:-$ARTIFACTS_ROOT/Asterion-TrollStore.ipa}"
PACKAGE_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/asterion-trollstore.XXXXXX")"

cleanup() {
  rm -rf "$PACKAGE_ROOT"
}
trap cleanup EXIT

mkdir -p "$ARTIFACTS_ROOT"

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

mkdir -p "$PACKAGE_ROOT/Payload"
cp -R "${APP_PATH}" "$PACKAGE_ROOT/Payload/"
(
  cd "$PACKAGE_ROOT"
  zip -rq "${IPA_PATH}" Payload
)

echo "==> IPA ready: ${IPA_PATH}"
echo "    AirDrop it to your device and open with TrollStore, or"
echo "    serve its directory with: python3 -m http.server 8080"
