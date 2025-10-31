#!/usr/bin/env bash
set -euo pipefail

YABAI_BIN=/opt/homebrew/bin/yabai
JQ_BIN=/opt/homebrew/bin/jq
PYTHON_BIN=${PYTHON_BIN:-/usr/bin/python3}
PLUGIN_DIR="$HOME/.config/sketchybar/plugins"
CONFIG_FILE="$PLUGIN_DIR/windows_config.sh"
SKETCHYBAR_BIN=/opt/homebrew/bin/sketchybar

if [ -f "$CONFIG_FILE" ]; then
  # shellcheck disable=SC1090
  source "$CONFIG_FILE"
fi
: "${EXCLUDED_APPS:=()}"
: "${EXCLUDE_FLOATING_WINDOWS:=false}"
: "${INCLUDE_FLOATING_APPS:=()}"

if [ "$#" -ne 1 ]; then
  exit 0
fi

DIRECTION="$1"

CURRENT_ID=$($YABAI_BIN -m query --windows --window | $JQ_BIN -r '.id // empty')
if [ -z "$CURRENT_ID" ]; then
  exit 0
fi

SPACE_JSON=$($YABAI_BIN -m query --spaces --space)
WINDOWS_JSON=$($YABAI_BIN -m query --windows --space)

if [ "${#EXCLUDED_APPS[@]}" -gt 0 ]; then
  EXCLUDED_APPS_JSON=$(printf '%s
' "${EXCLUDED_APPS[@]}" | $JQ_BIN -R . | $JQ_BIN -s .)
else
  EXCLUDED_APPS_JSON='[]'
fi

if [ "$EXCLUDE_FLOATING_WINDOWS" = "true" ]; then
  EXCLUDE_FLOATING_JSON=true
else
  EXCLUDE_FLOATING_JSON=false
fi

if [ "${#INCLUDE_FLOATING_APPS[@]}" -gt 0 ]; then
  INCLUDE_FLOATING_JSON=$(printf '%s
' "${INCLUDE_FLOATING_APPS[@]}" | $JQ_BIN -R . | $JQ_BIN -s .)
else
  INCLUDE_FLOATING_JSON='[]'
fi

WINDOW_IDS=()
if [ -x "$PLUGIN_DIR/window_order_state.py" ]; then
  export SPACE_JSON WINDOWS_JSON EXCLUDED_APPS_JSON EXCLUDE_FLOATING_JSON INCLUDE_FLOATING_JSON
  ORDERED_WINDOWS=$($PYTHON_BIN "$PLUGIN_DIR/window_order_state.py" order)
  if [ -n "$ORDERED_WINDOWS" ]; then
    while IFS= read -r id; do
      [ -n "$id" ] && WINDOW_IDS+=("$id")
    done < <(printf '%s
' "$ORDERED_WINDOWS" | $JQ_BIN -r '.[].id')
  fi
fi

if [ ${#WINDOW_IDS[@]} -eq 0 ]; then
  while IFS= read -r id; do
    [ -n "$id" ] && WINDOW_IDS+=("$id")
  done < <(printf '%s
' "$SPACE_JSON" | $JQ_BIN -r '.windows[]?')
fi

WINDOW_COUNT=${#WINDOW_IDS[@]}
if [ "$WINDOW_COUNT" -lt 2 ]; then
  exit 0
fi

CURRENT_INDEX=-1
for idx in "${!WINDOW_IDS[@]}"; do
  if [ "${WINDOW_IDS[$idx]}" = "$CURRENT_ID" ]; then
    CURRENT_INDEX=$idx
    break
  fi
done

if [ "$CURRENT_INDEX" -lt 0 ]; then
  exit 0
fi

TARGET_INDEX=-1
case "$DIRECTION" in
  prev|left)
    if [ "$CURRENT_INDEX" -gt 0 ]; then
      TARGET_INDEX=$((CURRENT_INDEX - 1))
    fi
    ;;
  next|right)
    if [ "$CURRENT_INDEX" -lt $((WINDOW_COUNT - 1)) ]; then
      TARGET_INDEX=$((CURRENT_INDEX + 1))
    fi
    ;;
  *)
    exit 0
    ;;
esac

if [ "$TARGET_INDEX" -lt 0 ]; then
  exit 0
fi

TARGET_ID=${WINDOW_IDS[$TARGET_INDEX]}
if [ -z "$TARGET_ID" ]; then
  exit 0
fi

CURRENT_FLOATING=$(printf '%s\n' "$WINDOWS_JSON" | $JQ_BIN -r --arg id "$CURRENT_ID" 'map(select(.id == ($id | tonumber))) | .[0]."is-floating" // false')
TARGET_FLOATING=$(printf '%s\n' "$WINDOWS_JSON" | $JQ_BIN -r --arg id "$TARGET_ID" 'map(select(.id == ($id | tonumber))) | .[0]."is-floating" // false')

SWAP_ALLOWED=true
if [ "$CURRENT_FLOATING" = "true" ] || [ "$TARGET_FLOATING" = "true" ]; then
  SWAP_ALLOWED=false
fi

SWAP_SUCCESS=false
if [ "$SWAP_ALLOWED" = "true" ]; then
  if $YABAI_BIN -m window --swap "$TARGET_ID" >/dev/null 2>&1; then
    SWAP_SUCCESS=true
    $YABAI_BIN -m window --focus "$CURRENT_ID" >/dev/null 2>&1 || true
  fi
else
  SWAP_SUCCESS=true
fi

if [ "$SWAP_SUCCESS" = "true" ]; then
  if [ -x "$PLUGIN_DIR/window_order_state.py" ]; then
    SPACE_JSON=$($YABAI_BIN -m query --spaces --space)
    WINDOWS_JSON=$($YABAI_BIN -m query --windows --space)
    export SPACE_JSON WINDOWS_JSON EXCLUDED_APPS_JSON EXCLUDE_FLOATING_JSON INCLUDE_FLOATING_JSON
    $PYTHON_BIN "$PLUGIN_DIR/window_order_state.py" swap "$CURRENT_ID" "$TARGET_ID" >/dev/null 2>&1 || true
  fi
  $SKETCHYBAR_BIN --trigger windows_update >/dev/null 2>&1 || true
fi
