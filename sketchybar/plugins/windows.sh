#!/usr/bin/env bash

# -----------------------------------------------------------------------------
# i3-like Window List with Equal Space Division
# Creates individual SketchyBar items for each window with equal width
# -----------------------------------------------------------------------------

SKETCHYBAR_BIN=/opt/homebrew/bin/sketchybar
YABAI_BIN=/opt/homebrew/bin/yabai
JQ_BIN=/opt/homebrew/bin/jq

TEAL_COLOR=0xff285577
WHITE_COLOR=0xffffffff
DARK_GRAY=0xff333333
BORDER_COLOR_ACTIVE=0xff4c7899
BORDER_COLOR_INACTIVE=0xff5f676a

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.window_focus_state"
PYTHON_BIN=${PYTHON_BIN:-/usr/bin/python3}
# shellcheck source=plugins/windows_config.sh
source "$SCRIPT_DIR/windows_config.sh"
: "${EXCLUDED_APPS:=()}"
: "${EXCLUDE_FLOATING_WINDOWS:=false}"
: "${INCLUDE_FLOATING_APPS:=()}"

if [ "${#EXCLUDED_APPS[@]}" -gt 0 ]; then
    EXCLUDED_APPS_JSON=$(printf '%s\n' "${EXCLUDED_APPS[@]}" | "$JQ_BIN" -R . | "$JQ_BIN" -s .)
else
    EXCLUDED_APPS_JSON='[]'
fi

if [[ "${EXCLUDE_FLOATING_WINDOWS:-false}" == "true" ]]; then
    EXCLUDE_FLOATING_JSON=true
else
    EXCLUDE_FLOATING_JSON=false
fi

if [ "${#INCLUDE_FLOATING_APPS[@]}" -gt 0 ]; then
    INCLUDE_FLOATING_JSON=$(printf '%s\n' "${INCLUDE_FLOATING_APPS[@]}" | "$JQ_BIN" -R . | "$JQ_BIN" -s .)
else
    INCLUDE_FLOATING_JSON='[]'
fi

SPACE_JSON=$("$YABAI_BIN" -m query --spaces --space)
CURRENT_SPACE_ID=$(printf '%s\n' "$SPACE_JSON" | "$JQ_BIN" -r '.id // empty')
WINDOWS_JSON=$("$YABAI_BIN" -m query --windows --space)
export SPACE_JSON WINDOWS_JSON EXCLUDED_APPS_JSON EXCLUDE_FLOATING_JSON INCLUDE_FLOATING_JSON
ORDERED_WINDOWS=$("$PYTHON_BIN" "$SCRIPT_DIR/window_order_state.py" order)

INCLUDED_COUNT=$(printf '%s\n' "$ORDERED_WINDOWS" | "$JQ_BIN" 'length')
if ! [[ "$INCLUDED_COUNT" =~ ^[0-9]+$ ]] || [ "$INCLUDED_COUNT" -eq 0 ]; then
    "$SKETCHYBAR_BIN" --remove '/window_[0-9]+/'
    exit 0
fi

CURRENT_WINDOW_ID=$("$YABAI_BIN" -m query --windows --window | "$JQ_BIN" -r '.id // empty')

MANUAL_FOCUSED_INDEX=-1
if [ -f "$STATE_FILE" ] && [ -n "$CURRENT_SPACE_ID" ]; then
    if "$JQ_BIN" -e '.' "$STATE_FILE" >/dev/null 2>&1; then
        VALUE=$("$JQ_BIN" -r --arg space "$CURRENT_SPACE_ID" 'try .[$space] // empty' "$STATE_FILE" 2>/dev/null)
        if [[ "$VALUE" =~ ^[0-9]+$ ]]; then
            MANUAL_FOCUSED_INDEX=$VALUE
        fi
    else
        MANUAL_CONTENT=$(tr -d '\n' <"$STATE_FILE" 2>/dev/null)
        if [[ "$MANUAL_CONTENT" =~ ^[0-9]+$ ]]; then
            MANUAL_FOCUSED_INDEX=$MANUAL_CONTENT
        fi
    fi
fi

if [ -n "$CURRENT_WINDOW_ID" ]; then
    MANUAL_FOCUSED_INDEX=-1
fi

SCREEN_WIDTH=$("$YABAI_BIN" -m query --displays --display | "$JQ_BIN" -r '.frame.w | floor')
if ! [[ "$SCREEN_WIDTH" =~ ^[0-9]+$ ]]; then
    SCREEN_WIDTH=0
fi

WINDOW_WIDTH=120
if [ "$INCLUDED_COUNT" -gt 0 ] && [ "$SCREEN_WIDTH" -gt 0 ]; then
    WINDOW_WIDTH=$((SCREEN_WIDTH / INCLUDED_COUNT))
    if [ "$WINDOW_WIDTH" -lt 120 ]; then
        WINDOW_WIDTH=120
    fi
fi

COMMANDS=(--remove '/window_[0-9]+/')

COUNT=1
while IFS= read -r -d '' APP \
      && IFS= read -r -d '' TITLE \
      && IFS= read -r -d '' ID; do
    if [ -z "$ID" ]; then
        continue
    fi

    TITLE=${TITLE//$'\n'/ }
    if [ "$TITLE" = "null" ]; then
        TITLE=""
    fi

    if [ -n "$TITLE" ]; then
        LABEL="[$COUNT] $APP: $TITLE"
    else
        LABEL="[$COUNT] $APP"
    fi

    INDEX=$((COUNT - 1))

    if [ -n "$CURRENT_WINDOW_ID" ] && [ "$ID" = "$CURRENT_WINDOW_ID" ]; then
        BG_COLOR=$TEAL_COLOR
        BORDER_COLOR=$BORDER_COLOR_ACTIVE
    elif (( MANUAL_FOCUSED_INDEX == INDEX )); then
        BG_COLOR=$TEAL_COLOR
        BORDER_COLOR=$BORDER_COLOR_ACTIVE
    else
        BG_COLOR=$DARK_GRAY
        BORDER_COLOR=$BORDER_COLOR_INACTIVE
    fi

    CLICK_SCRIPT="$HOME/.config/sketchybar/plugins/focus_window.sh $COUNT"

    COMMANDS+=(--add item "window_$COUNT" left)
    COMMANDS+=(--set "window_$COUNT" \
        "label=$LABEL" \
        "label.color=$WHITE_COLOR" \
        "label.font=Menlo:Regular:10.0" \
        "label.padding_left=5" \
        "label.padding_right=5" \
        "label.width=dynamic" \
        "background.color=$BG_COLOR" \
        "background.drawing=on" \
        "background.height=16" \
        "background.corner_radius=0" \
        "background.border_color=$BORDER_COLOR" \
        "background.border_width=1" \
        "width=$WINDOW_WIDTH" \
        "scroll_texts=on" \
        "click_script=$CLICK_SCRIPT")

    COUNT=$((COUNT + 1))
done < <(printf '%s\n' "$ORDERED_WINDOWS" | "$JQ_BIN" -r '.[] | "\(.app)\u0000\(.title // "")\u0000\(.id)\u0000"')

if [ "${#COMMANDS[@]}" -gt 0 ]; then
    "$SKETCHYBAR_BIN" "${COMMANDS[@]}"
fi
