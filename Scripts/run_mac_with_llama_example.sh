#!/usr/bin/env bash
set -euo pipefail

cat <<'EOF'
1. Build and run CardioConsultMac in Xcode.
2. Open Gemma4 Settings.
3. Example llama-cli path:
   /opt/homebrew/bin/llama-cli
4. Example model path:
   /Users/<you>/Models/gemma-4-4b-it-Q4_K_M.gguf

The macOS target calls llama-cli via Process when both paths exist.
EOF

