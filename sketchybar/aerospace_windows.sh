#!/usr/bin/env bash
set -euo pipefail

SKETCHYBAR_BIN=${SKETCHYBAR_BIN:-/opt/homebrew/bin/sketchybar}
AEROSPACE_BIN=${AEROSPACE_BIN:-$(launchctl getenv AEROSPACE_BIN 2>/dev/null || command -v aerospace 2>/dev/null || echo /opt/homebrew/bin/aerospace)}
JQ_BIN=${JQ_BIN:-/opt/homebrew/bin/jq}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MONITOR_WIDTH_BIN="$SCRIPT_DIR/bin/monitor-width"

BAR_HEIGHT=16
source "$SCRIPT_DIR/log_bin.sh" 2>/dev/null || true
ITEM_PREFIX="window_"
DEFAULT_ITEM_WIDTH=160
LABEL_PADDING=10 # 5 left + 5 right

TEAL_COLOR=0xff285577
DARK_GRAY=0xff333333
WHITE_COLOR=0xffffffff
BORDER_COLOR_ACTIVE=0xff4c7899
BORDER_COLOR_INACTIVE=0xff5f676a

# Fetch current workspace windows (ordered by AeroSpace)
windows_json="$("$AEROSPACE_BIN" list-windows --workspace focused --json 2>/dev/null || printf '[]')"
window_count=$(printf '%s' "$windows_json" | "$JQ_BIN" 'length' 2>/dev/null || printf '0')

# Collect existing SketchyBar items (left to right order)
existing_window_items=()
while IFS= read -r item; do
  [[ -n "$item" ]] && existing_window_items+=("$item")
done < <(
  "$SKETCHYBAR_BIN" --query bar 2>/dev/null \
    | "$JQ_BIN" -r '.items[]? // empty' 2>/dev/null \
    | grep "^${ITEM_PREFIX}" || true
)

# If there are no AeroSpace windows, remove lingering bar items
if ! [[ "$window_count" =~ ^[0-9]+$ ]] || [[ "$window_count" -eq 0 ]]; then
  if [[ ${#existing_window_items[@]} -gt 0 ]]; then
    for item in "${existing_window_items[@]}"; do
      "$SKETCHYBAR_BIN" --remove "$item"
    done
  fi
  exit 0
fi

# Determine monitor width using compiled helper (falls back to 0 on failure)
monitor_name="$("$AEROSPACE_BIN" list-windows --workspace focused --format '%{monitor-name}' 2>/dev/null | head -n 1 | tr -d '\n')"
monitor_width=0
if [[ -x "$MONITOR_WIDTH_BIN" ]]; then
  if [[ -n "$monitor_name" ]]; then
    monitor_width=$("$MONITOR_WIDTH_BIN" "$monitor_name" 2>/dev/null || printf '0')
  else
    monitor_width=$("$MONITOR_WIDTH_BIN" 2>/dev/null || printf '0')
  fi
fi
if ! [[ "$monitor_width" =~ ^[0-9]+$ ]]; then
  monitor_width=0
fi

# Compute evenly distributed width
item_width=$DEFAULT_ITEM_WIDTH
if [[ "$monitor_width" -gt 0 ]]; then
  calculated=$(( monitor_width / window_count ))
  if [[ "$calculated" -gt 0 ]]; then
    item_width=$calculated
  fi
fi

label_width=$(( item_width - LABEL_PADDING ))
if [[ "$label_width" -lt 0 ]]; then
  label_width=0
fi

focused_id="$("$AEROSPACE_BIN" list-windows --focused --format '%{window-id}' 2>/dev/null | tr -d '\n')"

# Track desired item names for removal + reorder
desired_order=()

sequence=1
while IFS= read -r window; do
  [[ -z "$window" ]] && continue

  window_id=$(printf '%s' "$window" | "$JQ_BIN" -r '.["window-id"] // empty' | tr -d '\n')
  [[ -z "$window_id" ]] && continue
  item_name="${ITEM_PREFIX}${window_id}"

  desired_order+=("$item_name")

  if ! "$SKETCHYBAR_BIN" --query "$item_name" >/dev/null 2>&1; then
    "$SKETCHYBAR_BIN" --add item "$item_name" left
  fi

  app_name=$(printf '%s' "$window" | "$JQ_BIN" -r '.["app-name"] // ""' | tr -d '\n')
  window_title=$(printf '%s' "$window" | "$JQ_BIN" -r '.["window-title"] // ""' | tr -d '\n')
  window_title=${window_title//$'\n'/ }

  label="[$sequence] $app_name"
  if [[ -n "$window_title" ]]; then
    label="$label: $window_title"
  fi

  bg_color=$DARK_GRAY
  border_color=$BORDER_COLOR_INACTIVE
  if [[ -n "$focused_id" && "$window_id" == "$focused_id" ]]; then
    bg_color=$TEAL_COLOR
    border_color=$BORDER_COLOR_ACTIVE
  fi

  click_cmd="$AEROSPACE_BIN focus --window-id ${window_id}"

  "$SKETCHYBAR_BIN" --set "$item_name" \
    "label=$label" \
    "label.color=$WHITE_COLOR" \
    "label.font=Menlo:Regular:10.0" \
    "label.padding_left=5" \
    "label.padding_right=5" \
    "label.width=$label_width" \
    "label.align=left" \
    "background.color=$bg_color" \
    "background.drawing=on" \
    "background.height=$BAR_HEIGHT" \
    "background.corner_radius=0" \
    "background.border_color=$border_color" \
    "background.border_width=1" \
    "width=$item_width" \
    "scroll_texts=on" \
    "click_script=$click_cmd"

  ((sequence+=1))
done < <(printf '%s' "$windows_json" | "$JQ_BIN" -c '.[]')

# Remove window items no longer present
for item in "${existing_window_items[@]}"; do
  if ! printf '%s\n' "${desired_order[@]}" | grep -Fx "$item" >/dev/null 2>&1; then
    "$SKETCHYBAR_BIN" --remove "$item"
  fi
done

# Ensure SketchyBar order matches AeroSpace order
if [[ ${#desired_order[@]} -gt 0 ]]; then
  "$SKETCHYBAR_BIN" --reorder "${desired_order[@]}"
fi

exit 0
