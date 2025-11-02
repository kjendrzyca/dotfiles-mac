#!/usr/bin/env bash
set -euo pipefail
AEROSPACE_BIN=${AEROSPACE_BIN:-$(command -v aerospace 2>/dev/null || echo /opt/homebrew/bin/aerospace)}
echo "$(date): BIN=$AEROSPACE_BIN" >> ~/.config/sketchybar/aero_bin.log
