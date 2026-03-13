#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-ensure}"
BORDERS_BIN="/opt/homebrew/bin/borders"
LOG_FILE="/tmp/borders.log"

if [[ ! -x "$BORDERS_BIN" ]]; then
  printf 'borders binary not found: %s\n' "$BORDERS_BIN" >&2
  exit 1
fi

case "$MODE" in
  ensure)
    ;;
  restart)
    pkill -x borders 2>/dev/null || true
    sleep 0.2
    ;;
  *)
    printf 'usage: %s [ensure|restart]\n' "$0" >&2
    exit 1
    ;;
esac

if pgrep -x borders >/dev/null 2>&1; then
  exit 0
fi

nohup "$BORDERS_BIN" \
  active_color=0xff4c9df3 \
  inactive_color=0xff5f676a \
  width=2.0 \
  order=above \
  'blacklist=Loom,Wispr Flow' \
  >"$LOG_FILE" 2>&1 &
