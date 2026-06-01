#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodebuild \
  -project CardioConsultApple.xcodeproj \
  -scheme CardioConsultiOS \
  -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  build

echo "iOS simulator debug build complete."

