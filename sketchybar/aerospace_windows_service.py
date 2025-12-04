#!/usr/bin/env python3
"""
Long-lived renderer for SketchyBar window list driven by AeroSpace.

Maintains in-memory state to minimise redundant SketchyBar updates and avoid
process start-up overhead on every focus/workspace change.
"""

from __future__ import annotations

import json
import os
import signal
import socket
import subprocess
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path
from typing import Dict, List


CONFIG_DIR = Path(os.environ.get("SKETCHYBAR_CONFIG_DIR", Path.home() / ".config" / "sketchybar"))
CACHE_DIR = CONFIG_DIR / ".cache"
SOCKET_PATH = CACHE_DIR / "aerospace_windows.sock"

SKETCHYBAR_BIN = os.environ.get("SKETCHYBAR_BIN", "/opt/homebrew/bin/sketchybar")
AEROSPACE_BIN = os.environ.get(
    "AEROSPACE_BIN",
    os.popen("launchctl getenv AEROSPACE_BIN").read().strip() or "/opt/homebrew/bin/aerospace",
)
JQ_BIN = os.environ.get("JQ_BIN", "/opt/homebrew/bin/jq")
MONITOR_WIDTH_BIN = CONFIG_DIR / "bin" / "monitor-width"

SCROLL_TEXTS = os.environ.get("SKETCHYBAR_SCROLL_TEXTS", "off")
INSTANT_REDRAW = os.environ.get("SKETCHYBAR_INSTANT_REDRAW", "0").lower() in {"1", "true", "on", "yes"}

DEFAULT_ITEM_WIDTH = 160
LABEL_PADDING = 10
BAR_HEIGHT = 16
ITEM_PREFIX = "window_"

TEAL_COLOR = "0xff4c9df3"
DARK_GRAY = "0xff333333"
WHITE_COLOR = "0xffffffff"
BLACK_COLOR = "0xff000000"
BORDER_COLOR_ACTIVE = "0xff4c9df3"
BORDER_COLOR_INACTIVE = "0xff4c9df3"


class AeroSpaceError(RuntimeError):
    pass


def log(msg: str) -> None:
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    sys.stderr.write(f"[aerospace_service {timestamp}] {msg}\n")
    sys.stderr.flush()


def run_command(args: List[str], capture: bool = True) -> subprocess.CompletedProcess:
    return subprocess.run(
        args,
        check=False,
        text=True,
        capture_output=capture,
    )


def fetch_windows_json() -> List[Dict]:
    result = run_command([AEROSPACE_BIN, "list-windows", "--workspace", "focused", "--json"])
    if result.returncode != 0:
        raise AeroSpaceError(result.stderr.strip() or "list-windows failed")
    try:
        data = json.loads(result.stdout.strip() or "[]")
        if isinstance(data, list):
            return data
        raise ValueError("unexpected JSON structure")
    except json.JSONDecodeError as exc:
        raise AeroSpaceError(f"Failed to parse AeroSpace JSON: {exc}") from exc


def fetch_monitor_info() -> Dict[str, str]:
    monitor_name = ""
    monitor_width = 0

    result = run_command(
        [AEROSPACE_BIN, "list-windows", "--workspace", "focused", "--format", "%{monitor-name}"]
    )
    if result.returncode == 0:
        monitor_name = result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""

    result = run_command(
        [AEROSPACE_BIN, "list-windows", "--workspace", "focused", "--format", "%{monitor-width}"]
    )
    if result.returncode == 0:
        line = result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""
        try:
            monitor_width = int(line)
        except ValueError:
            monitor_width = 0

    if monitor_width <= 0 and MONITOR_WIDTH_BIN.exists():
        args = [str(MONITOR_WIDTH_BIN)]
        if monitor_name:
            args.append(monitor_name)
        result = run_command(args, capture=True)
        if result.returncode == 0:
            try:
                monitor_width = int(result.stdout.strip().splitlines()[0])
            except (ValueError, IndexError):
                monitor_width = 0

    return {"name": monitor_name, "width": monitor_width}


def fetch_focused_window_id() -> str:
    result = run_command([AEROSPACE_BIN, "list-windows", "--focused", "--format", "%{window-id}"])
    if result.returncode != 0:
        return ""
    return result.stdout.strip().splitlines()[0] if result.stdout.strip() else ""


def window_label(seq: int, app_name: str, title: str) -> str:
    safe_title = title.replace("\n", " ").strip()
    label = f"[{seq}] {app_name}"
    if safe_title:
        label = f"{label}: {safe_title}"
    return label


def ensure_socket_directory() -> None:
    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    if SOCKET_PATH.exists():
        try:
            SOCKET_PATH.unlink()
        except OSError as err:
            log(f"Failed to unlink stale socket: {err}")


def cleanup_socket(*_args) -> None:
    if SOCKET_PATH.exists():
        try:
            SOCKET_PATH.unlink()
        except OSError:
            pass
    sys.exit(0)


def run_sketchybar(args: List[str]) -> None:
    result = run_command([SKETCHYBAR_BIN, *args], capture=True)
    if result.returncode != 0:
        log(f"SketchyBar command failed: {' '.join(args)} -> {result.stderr.strip()}")


@dataclass
class WindowState:
    order: List[str] = field(default_factory=list)
    props: Dict[str, Dict[str, str]] = field(default_factory=dict)

    def reset(self) -> None:
        self.order = []
        self.props = {}


class Renderer:
    def __init__(self) -> None:
        self.state = WindowState()

    def update(self) -> None:
        try:
            windows = fetch_windows_json()
        except AeroSpaceError as err:
            log(str(err))
            return

        if not windows:
            self._clear_bar()
            return

        focus_id = fetch_focused_window_id()
        monitor_info = fetch_monitor_info()
        window_count = len(windows)
        item_width = DEFAULT_ITEM_WIDTH
        monitor_width = monitor_info.get("width", 0) if monitor_info else 0
        if isinstance(monitor_width, int) and monitor_width > 0 and window_count > 0:
            calculated = monitor_width // window_count
            if calculated > 0:
                item_width = calculated
        label_width = max(item_width - LABEL_PADDING, 0)

        new_order: List[str] = []
        new_props: Dict[str, Dict[str, str]] = {}

        for idx, window in enumerate(windows, start=1):
            window_id = str(window.get("window-id", "")).strip()
            if not window_id:
                continue
            item_name = f"{ITEM_PREFIX}{window_id}"
            new_order.append(item_name)

            app_name = str(window.get("app-name", "")).strip()
            window_title = str(window.get("window-title", "")).strip()

            bg_color = DARK_GRAY
            border_color = BORDER_COLOR_INACTIVE
            label_color = WHITE_COLOR
            if focus_id and window_id == focus_id:
                bg_color = TEAL_COLOR
                border_color = BORDER_COLOR_ACTIVE
                label_color = BLACK_COLOR

            props = {
                "label": window_label(idx, app_name, window_title),
                "label.color": label_color,
                "label.font": "Menlo:Regular:10.0",
                "label.padding_left": "5",
                "label.padding_right": "5",
                "label.width": str(label_width),
                "label.align": "left",
                "background.color": bg_color,
                "background.drawing": "on",
                "background.height": str(BAR_HEIGHT),
                "background.corner_radius": "0",
                "background.border_color": border_color,
                "background.border_width": "1",
                "width": str(item_width),
                "scroll_texts": SCROLL_TEXTS,
                "click_script": f"{AEROSPACE_BIN} focus --window-id {window_id}",
            }
            new_props[item_name] = props

        # Add new items and update changed properties
        for item_name, props in new_props.items():
            if item_name not in self.state.props:
                run_sketchybar(["--add", "item", item_name, "left"])
                self._set_properties(item_name, props)
            else:
                self._set_differences(item_name, props)

        # Remove stale windows
        for item_name in list(self.state.order):
            if item_name not in new_order:
                run_sketchybar(["--remove", item_name])
                self.state.props.pop(item_name, None)

        # Reorder if needed
        if new_order != self.state.order and new_order:
            run_sketchybar(["--reorder", *new_order])

        self.state.order = new_order
        self.state.props = new_props

    def _clear_bar(self) -> None:
        for item_name in self.state.order:
            run_sketchybar(["--remove", item_name])
        self.state.reset()

    def _set_properties(self, item_name: str, props: Dict[str, str]) -> None:
        if INSTANT_REDRAW:
            run_sketchybar(["--set", item_name, "drawing=off"])
        args = ["--set", item_name]
        for key, value in props.items():
            args.append(f"{key}={value}")
        run_sketchybar(args)
        if INSTANT_REDRAW:
            run_sketchybar(["--set", item_name, "drawing=on"])

    def _set_differences(self, item_name: str, props: Dict[str, str]) -> None:
        previous = self.state.props.get(item_name, {})
        diffs = {k: v for k, v in props.items() if previous.get(k) != v}
        if not diffs:
            return
        self._set_properties(item_name, {**previous, **diffs})


def serve() -> None:
    ensure_socket_directory()
    renderer = Renderer()

    sock = socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM)
    sock.bind(str(SOCKET_PATH))
    os.chmod(str(SOCKET_PATH), 0o666)

    signal.signal(signal.SIGINT, cleanup_socket)
    signal.signal(signal.SIGTERM, cleanup_socket)

    # Populate on launch
    renderer.update()

    while True:
        try:
            data, _addr = sock.recvfrom(4096)
        except OSError as err:
            log(f"Socket error: {err}")
            time.sleep(0.5)
            continue

        message = data.decode("utf-8", "ignore").strip().lower()
        if message in {"update", ""}:
            renderer.update()
        elif message == "reload":
            renderer.state.reset()
            renderer.update()
        elif message == "quit":
            cleanup_socket()
        else:
            log(f"Unknown message '{message}'")


def main() -> None:
    try:
        serve()
    except Exception as err:
        log(f"Fatal error: {err}")
        cleanup_socket()


if __name__ == "__main__":
    main()
