#!/usr/bin/env bash
set -euo pipefail

# Move "sticky" overlay windows (e.g. Wispr Flow Status) to the currently
# focused AeroSpace workspace.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OVERLAY_CONFIG="$SCRIPT_DIR/overlay-windows.json"

AERO="$(launchctl getenv AEROSPACE_BIN 2>/dev/null || echo /opt/homebrew/bin/aerospace)"
JQ="/opt/homebrew/bin/jq"
EXPECT="/usr/bin/expect"

# Prevent overlapping runs (on-focus-changed can fire often).
LOCK_DIR="/tmp/aerospace_sticky_overlays.lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  exit 0
fi
cleanup() { rmdir "$LOCK_DIR" 2>/dev/null || true; }
trap cleanup EXIT

focused_ws="${AEROSPACE_FOCUSED_WORKSPACE:-}"
if [[ -n "${focused_ws}" ]]; then
  # When called from exec-on-workspace-change, give AeroSpace a moment to settle.
  sleep 0.05
else
  focused_ws="$($AERO list-workspaces --focused 2>/dev/null | head -n1 | tr -d '\n' || true)"
  if [[ -z "${focused_ws}" ]]; then
    focused_ws="$($AERO list-windows --focused --format '%{workspace}' 2>/dev/null | head -n1 | tr -d '\n' || true)"
  fi
fi
[[ -z "${focused_ws}" ]] && exit 0

# Collect window IDs that match overlay rules with sticky=true.
all_windows="$($AERO list-windows --all --json 2>/dev/null || echo '[]')"
sticky_wids="$(
  printf '%s' "$all_windows" \
    | "$JQ" -r --slurpfile overlays "$OVERLAY_CONFIG" '
        ($overlays[0] | map(select(.sticky == true))) as $sticky |
        .[]
        | select(. as $w | ($sticky | any(
            (."app-name" == $w."app-name") and
            (if ."window-title" then ."window-title" == $w."window-title" else true end)
          )))
        | ."window-id"
      ' 2>/dev/null
)"

[[ -z "${sticky_wids}" ]] && exit 0

while IFS= read -r wid; do
  [[ -z "${wid}" ]] && continue
  # AeroSpace v0.20.0+ requires TTY for move-node-to-workspace when run from
  # non-interactive contexts.
  out="$($EXPECT -c "log_user 0; spawn $AERO move-node-to-workspace --fail-if-noop --window-id $wid $focused_ws; expect eof; catch wait result; exit [lindex \$result 3]" 2>&1)" || true
  # Ignore no-op moves, but surface unexpected errors.
  if [[ -n "${out}" && "${out}" != *"already belongs to workspace"* ]]; then
    printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "sticky-overlays: wid=${wid} target_ws=${focused_ws} -> ${out}" >>/tmp/aerospace_sticky_overlays.log
  fi
done <<<"$sticky_wids"
