#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

ASTERION_DEVICE_ID="${ASTERION_DEVICE_ID:-00008132-001A79013E7A801C}" \
ASTERION_DERIVED_DATA_PATH="${ASTERION_DERIVED_DATA_PATH:-$WORKSPACE_ROOT/.artifacts/ios/ipad-device}" \
"$SCRIPT_DIR/build-install-launch-iphone.sh"
