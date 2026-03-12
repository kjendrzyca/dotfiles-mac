#!/usr/bin/env bash
set -euo pipefail

# Filtered DFS navigation and swap for AeroSpace.
# Reads overlay window definitions from overlay-windows.json and skips them
# during focus/swap operations.
#
# Usage: navigate.sh <focus-next|focus-prev|swap-next|swap-prev>

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_CONFIG="$SCRIPT_DIR/overlay-windows.json"
AERO=$(launchctl getenv AEROSPACE_BIN 2>/dev/null || echo /opt/homebrew/bin/aerospace)
JQ=/opt/homebrew/bin/jq

ACTION="${1:-}"
if [[ -z "$ACTION" ]]; then
  echo "Usage: $0 <focus-next|focus-prev|swap-next|swap-prev>" >&2
  exit 1
fi

# jq filter: returns true if a window matches any overlay rule.
# overlay-windows.json entries have "app-name" and optionally "window-title".
JQ_IS_OVERLAY='
  . as $w | ($overlays[0] | any(
    (."app-name" == $w."app-name") and
    (if ."window-title" then ."window-title" == $w."window-title" else true end)
  ))
'

# jq filter: removes overlay windows from the list.
JQ_FILTER_OVERLAYS="[.[] | select(($JQ_IS_OVERLAY) | not)]"

# Execute an aerospace command. Use expect to provide a pseudo-TTY when
# called from non-interactive contexts (AeroSpace v0.20.0+ requirement).
run_aero() {
  if [ -t 0 ]; then
    "$AERO" "$@" 2>/dev/null
  else
    expect -c "spawn $AERO $*; expect eof" >/dev/null 2>&1
  fi
}

# --- Gather state ---

all_windows=$("$AERO" list-windows --workspace focused --json 2>/dev/null || echo '[]')
filtered=$(printf '%s' "$all_windows" | "$JQ" --slurpfile overlays "$OVERLAY_CONFIG" "$JQ_FILTER_OVERLAYS" 2>/dev/null || echo '[]')

count=$(printf '%s' "$filtered" | "$JQ" 'length')
if [[ "$count" -eq 0 ]]; then
  exit 0
fi

focused_id=$("$AERO" list-windows --focused --format '%{window-id}' 2>/dev/null | tr -d '\n')

# Find index of focused window in the filtered (non-overlay) list.
current_idx=-1
if [[ -n "$focused_id" ]]; then
  current_idx=$(printf '%s' "$filtered" | "$JQ" --arg fid "$focused_id" '
    to_entries | map(select(.value."window-id" == ($fid | tonumber))) | .[0].key // -1
  ')
fi

# If focused window is an overlay itself, pick a sensible default.
if [[ "$current_idx" -lt 0 ]]; then
  case "$ACTION" in
    focus-next|swap-next) current_idx=0 ;;
    focus-prev|swap-prev) current_idx=$((count - 1)) ;;
  esac
fi

# Target index with wrap-around.
case "$ACTION" in
  focus-next|swap-next) target_idx=$(( (current_idx + 1) % count )) ;;
  focus-prev|swap-prev) target_idx=$(( (current_idx - 1 + count) % count )) ;;
  *) echo "Unknown action: $ACTION" >&2; exit 1 ;;
esac

target_id=$(printf '%s' "$filtered" | "$JQ" -r ".[$target_idx].\"window-id\"")
[[ -z "$target_id" || "$target_id" == "null" ]] && exit 0

# --- Execute ---

case "$ACTION" in
  focus-next|focus-prev)
    run_aero focus --window-id "$target_id"
    ;;
  swap-next|swap-prev)
    # swap doesn't accept a target window-id; it swaps relative to DFS order.
    # Calculate how many raw DFS swap steps are needed to reach the target,
    # accounting for overlay windows sitting between source and target.
    direction="dfs-next"
    [[ "$ACTION" == "swap-prev" ]] && direction="dfs-prev"

    # Find positions in the FULL (unfiltered) window list.
    focused_raw_idx=$(printf '%s' "$all_windows" | "$JQ" --arg fid "$focused_id" '
      to_entries | map(select(.value."window-id" == ($fid | tonumber))) | .[0].key // -1
    ')
    target_raw_idx=$(printf '%s' "$all_windows" | "$JQ" --arg tid "$target_id" '
      to_entries | map(select(.value."window-id" == ($tid | tonumber))) | .[0].key // -1
    ')

    if [[ "$focused_raw_idx" -lt 0 || "$target_raw_idx" -lt 0 ]]; then
      exit 0
    fi

    # Number of individual DFS swap steps needed.
    raw_count=$(printf '%s' "$all_windows" | "$JQ" 'length')
    if [[ "$ACTION" == "swap-next" ]]; then
      if [[ "$target_raw_idx" -gt "$focused_raw_idx" ]]; then
        steps=$(( target_raw_idx - focused_raw_idx ))
      else
        steps=$(( raw_count - focused_raw_idx + target_raw_idx ))
      fi
    else
      if [[ "$focused_raw_idx" -gt "$target_raw_idx" ]]; then
        steps=$(( focused_raw_idx - target_raw_idx ))
      else
        steps=$(( focused_raw_idx + raw_count - target_raw_idx ))
      fi
    fi

    for (( i = 0; i < steps; i++ )); do
      run_aero swap "$direction"
    done

    # swap doesn't change focus, so no AeroSpace hook fires automatically.
    # Trigger a SketchyBar update to reflect the new window order.
    /opt/homebrew/bin/sketchybar --trigger aerospace_windows_update KIND=windows
    ;;
esac
