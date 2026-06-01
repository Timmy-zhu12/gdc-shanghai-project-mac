#!/usr/bin/env bash
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: Scripts/copy_models_to_ios_simulator.sh <SIMULATOR_UDID>"
  exit 1
fi

SIM_UDID="$1"
APP_GROUP_DIR="$(xcrun simctl get_app_container "$SIM_UDID" com.cardioconsult.apple.ios data)"
mkdir -p "$APP_GROUP_DIR/Documents/Models"
cp Models/gemma-4-4b-it-Q4_K_M.gguf "$APP_GROUP_DIR/Documents/Models/" 2>/dev/null || true
cp Models/gemma-4-4b-mmproj-Q4_0.gguf "$APP_GROUP_DIR/Documents/Models/" 2>/dev/null || true
echo "Copied available model files to: $APP_GROUP_DIR/Documents/Models"

