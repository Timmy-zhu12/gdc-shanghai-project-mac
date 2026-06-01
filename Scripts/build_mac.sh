#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

xcodebuild \
  -project CardioConsultApple.xcodeproj \
  -scheme CardioConsultMac \
  -configuration Debug \
  -destination 'platform=macOS' \
  build

echo "macOS debug build complete."

