#!/usr/bin/env bash
set -euo pipefail

SKETCHYBAR_BIN=/opt/homebrew/bin/sketchybar
YABAI_BIN=/opt/homebrew/bin/yabai
JQ_BIN=/opt/homebrew/bin/jq
PYTHON_BIN=${PYTHON_BIN:-/usr/bin/python3}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=plugins/windows_config.sh
source "$SCRIPT_DIR/windows_config.sh"
: "${EXCLUDED_APPS:=()}"
: "${EXCLUDE_FLOATING_WINDOWS:=false}"

if [ "${#EXCLUDED_APPS[@]}" -gt 0 ]; then
    EXCLUDED_APPS_JSON=$(printf '%s
' "${EXCLUDED_APPS[@]}" | "$JQ_BIN" -R . | "$JQ_BIN" -s .)
else
    EXCLUDED_APPS_JSON='[]'
fi

if [ "$EXCLUDE_FLOATING_WINDOWS" = "true" ]; then
    EXCLUDE_FLOATING_JSON=true
else
    EXCLUDE_FLOATING_JSON=false
fi

SPACE_JSON=$("$YABAI_BIN" -m query --spaces --space)
WINDOWS_JSON=$("$YABAI_BIN" -m query --windows --space)
export SPACE_JSON WINDOWS_JSON EXCLUDED_APPS_JSON EXCLUDE_FLOATING_JSON
"$PYTHON_BIN" "$SCRIPT_DIR/window_order_state.py" sync

"$SKETCHYBAR_BIN" --trigger windows_update
