#!/bin/bash
# macOS: open this file to configure/start the academy on this computer.
set -euo pipefail
cd "$(dirname "$0")"
if ! command -v python3 >/dev/null 2>&1; then
  echo 'Install Python 3.12 or newer, then open this launcher again.'
  read -r -p 'Press Enter to close.'
  exit 1
fi
python3 scripts/local.py desktop
