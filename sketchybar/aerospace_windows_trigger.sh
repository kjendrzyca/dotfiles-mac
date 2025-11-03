#!/usr/bin/env bash

set -euo pipefail

CONFIG_DIR="${SKETCHYBAR_CONFIG_DIR:-$HOME/.config/sketchybar}"
SOCKET_PATH="$CONFIG_DIR/.cache/aerospace_windows.sock"
LEGACY_SCRIPT="$CONFIG_DIR/aerospace_windows.sh"

send_message() {
  /usr/bin/env python3 - <<'PY' "$SOCKET_PATH" "$1"
import os
import socket
import sys

sock_path = sys.argv[1]
message = sys.argv[2] if len(sys.argv) > 2 else "update"

if not os.path.exists(sock_path):
    sys.exit(1)

sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
try:
    sock.connect(sock_path)
    sock.sendall(message.encode("utf-8"))
except OSError:
    sys.exit(1)
finally:
    sock.close()
PY
}

if [[ -S "$SOCKET_PATH" ]]; then
  if send_message "update"; then
    exit 0
  fi
fi

exit 1
