#!/usr/bin/env bash
set -euo pipefail

ASTERION_DEVICE_ID="${ASTERION_DEVICE_ID:-00008132-001A79013E7A801C}" \
ASTERION_DERIVED_DATA_PATH="${ASTERION_DERIVED_DATA_PATH:-.build/ipad-device}" \
./scripts/build-install-launch-iphone.sh
