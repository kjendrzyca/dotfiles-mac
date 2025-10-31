#!/usr/bin/env bash

# This script handles both directional navigation and direct window focusing
# Usage:
#   focus_window.sh prev|next    - Navigate between windows
#   focus_window.sh NUMBER       - Focus window by index (from clicking)

PARAM=$1

SKETCHYBAR_BIN=/opt/homebrew/bin/sketchybar
YABAI_BIN=/opt/homebrew/bin/yabai
JQ_BIN=/opt/homebrew/bin/jq
OSASCRIPT_BIN=/usr/bin/osascript

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATE_FILE="$SCRIPT_DIR/.window_focus_state"
PYTHON_BIN=${PYTHON_BIN:-/usr/bin/python3}
# shellcheck source=plugins/windows_config.sh
source "$SCRIPT_DIR/windows_config.sh"
: "${EXCLUDED_APPS:=()}"
: "${EXCLUDE_FLOATING_WINDOWS:=false}"
: "${INCLUDE_FLOATING_APPS:=()}"

write_focus_state() {
    local idx="$1"
    local space="$2"
    [ -z "$space" ] && return

    if ! [[ "$idx" =~ ^[0-9]+$ ]]; then
        if [ -f "$STATE_FILE" ] && "$JQ_BIN" -e '.' "$STATE_FILE" >/dev/null 2>&1; then
            local tmp
            tmp=$(mktemp "$STATE_FILE.XXXXXX") || return
            if "$JQ_BIN" --arg space "$space" 'del(.[$space])' "$STATE_FILE" >"$tmp" 2>/dev/null; then
                mv "$tmp" "$STATE_FILE"
            else
                rm -f "$tmp"
            fi
        fi
        return
    fi

    local tmp
    tmp=$(mktemp "$STATE_FILE.XXXXXX") || return
    if [ -f "$STATE_FILE" ] && "$JQ_BIN" -e '.' "$STATE_FILE" >/dev/null 2>&1; then
        if ! "$JQ_BIN" --arg space "$space" --argjson idx "$idx" '(. // {}) | .[$space] = $idx' "$STATE_FILE" >"$tmp" 2>/dev/null; then
            printf '{"%s": %s}\n' "$space" "$idx" >"$tmp"
        fi
    else
        printf '{"%s": %s}\n' "$space" "$idx" >"$tmp"
    fi
    mv "$tmp" "$STATE_FILE"
}

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
    exit 0
fi

INCLUDED_WINDOW_IDS=()
INCLUDED_WINDOW_APPS=()
while IFS=$'\t' read -r ID APP; do
    INCLUDED_WINDOW_IDS+=("$ID")
    INCLUDED_WINDOW_APPS+=("$APP")
done < <(printf '%s\n' "$ORDERED_WINDOWS" | "$JQ_BIN" -rc '.[] | [.id, .app] | @tsv')

INCLUDED_COUNT=${#INCLUDED_WINDOW_IDS[@]}
if [ "$INCLUDED_COUNT" -eq 0 ]; then
    exit 0
fi

FOCUSED_WINDOW_ID=$("$YABAI_BIN" -m query --windows --window | "$JQ_BIN" -r '.id // empty')

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

focus_window_by_index() {
    local index=$1

    if (( index < 0 || index >= INCLUDED_COUNT )); then
        return
    fi

    local target_window_id=${INCLUDED_WINDOW_IDS[$index]}
    local target_app=${INCLUDED_WINDOW_APPS[$index]}

    if [ -z "$target_window_id" ]; then
        return
    fi

    if ! "$YABAI_BIN" -m window --focus "$target_window_id" >/dev/null 2>&1; then
        if [ -n "$target_app" ] && [ -x "$OSASCRIPT_BIN" ]; then
            "$OSASCRIPT_BIN" - "$target_window_id" "$target_app" <<'OSA' >/dev/null 2>&1
on run argv
    set windowId to (item 1 of argv) as integer
    set appName to item 2 of argv
    tell application appName
        activate
        repeat with w in windows
            try
                if id of w is windowId then
                    set miniaturized of w to false
                    set index of w to 1
                    exit repeat
                end if
            end try
        end repeat
    end tell
end run
OSA
            sleep 0.05
            "$YABAI_BIN" -m window --focus "$target_window_id" >/dev/null 2>&1 || true
        fi
    fi

    write_focus_state "$index" "$CURRENT_SPACE_ID"
    "$SKETCHYBAR_BIN" --trigger window_list_update
}

FOCUSED_INDEX=-1
if [ -n "$FOCUSED_WINDOW_ID" ]; then
    for idx in "${!INCLUDED_WINDOW_IDS[@]}"; do
        if [[ "${INCLUDED_WINDOW_IDS[$idx]}" == "$FOCUSED_WINDOW_ID" ]]; then
            FOCUSED_INDEX=$idx
            break
        fi
    done
fi

if (( FOCUSED_INDEX >= 0 )); then
    write_focus_state "$FOCUSED_INDEX" "$CURRENT_SPACE_ID"
elif (( MANUAL_FOCUSED_INDEX >= 0 && MANUAL_FOCUSED_INDEX < INCLUDED_COUNT )); then
    FOCUSED_INDEX=$MANUAL_FOCUSED_INDEX
else
    write_focus_state "" "$CURRENT_SPACE_ID"
fi

if [[ "$PARAM" =~ ^[0-9]+$ ]]; then
    WINDOW_INDEX=$((PARAM - 1))
    focus_window_by_index "$WINDOW_INDEX"
    exit 0
fi

DIRECTION=$PARAM

if (( FOCUSED_INDEX == -1 )); then
    if [ "$DIRECTION" = "prev" ]; then
        TARGET_INDEX=$((INCLUDED_COUNT - 1))
    else
        TARGET_INDEX=0
    fi
else
    if [ "$DIRECTION" = "prev" ]; then
        TARGET_INDEX=$(((FOCUSED_INDEX - 1 + INCLUDED_COUNT) % INCLUDED_COUNT))
    else
        TARGET_INDEX=$(((FOCUSED_INDEX + 1) % INCLUDED_COUNT))
    fi
fi

focus_window_by_index "$TARGET_INDEX"
