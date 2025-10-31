#!/usr/bin/env python3
"""Maintain a stable window ordering per space for SketchyBar."""

from __future__ import annotations
import json
import os
import sys
from pathlib import Path
from typing import Any, Dict, List

SCRIPT_DIR = Path(__file__).resolve().parent
STATE_PATH = SCRIPT_DIR / '.window_order_state.json'
FOCUS_PATH = SCRIPT_DIR / '.window_focus_state'


def load_state() -> Dict[str, List[str]]:
    if STATE_PATH.exists():
        try:
            with STATE_PATH.open('r', encoding='utf-8') as fh:
                data = json.load(fh)
                if isinstance(data, dict):
                    return {str(k): [str(i) for i in v] for k, v in data.items() if isinstance(v, list)}
        except Exception:
            pass
    return {}


def save_state(state: Dict[str, List[str]]) -> None:
    tmp = STATE_PATH.with_suffix('.tmp')
    with tmp.open('w', encoding='utf-8') as fh:
        json.dump(state, fh)
    tmp.replace(STATE_PATH)


def reset_focus_state() -> None:
    try:
        FOCUS_PATH.unlink()
    except FileNotFoundError:
        pass


def parse_env_json(name: str, default: Any) -> Any:
    raw = os.environ.get(name)
    if raw is None:
        return default
    try:
        return json.loads(raw)
    except Exception:
        return default


def filter_windows(
    windows: List[dict],
    excluded_apps: set[str],
    exclude_floating: bool,
    include_floating_apps: set[str],
) -> Dict[str, dict]:
    filtered: Dict[str, dict] = {}
    for win in windows:
        if not isinstance(win, dict):
            continue
        win_id = win.get('id')
        if win_id is None:
            continue
        app = win.get('app') or ''
        if app in excluded_apps:
            continue
        if (
            exclude_floating
            and win.get('is-floating') is True
            and app not in include_floating_apps
        ):
            continue
        filtered[str(win_id)] = win
    return filtered


def geometry_sorted_ids(windows_map: Dict[str, dict]) -> List[str]:
    def sort_key(item: tuple[str, dict]) -> tuple[float, float, int]:
        wid, win = item
        frame = win.get('frame') or {}
        x = frame.get('x', 0)
        y = frame.get('y', 0)
        return (x, y, int(wid))

    return [wid for wid, _ in sorted(windows_map.items(), key=sort_key)]


def build_order(space: dict, windows_map: Dict[str, dict], state: Dict[str, List[str]]) -> List[str]:
    space_id = str(space.get('id'))
    saved = state.get(space_id, [])
    saved = [wid for wid in saved if wid in windows_map]

    geometry_order = geometry_sorted_ids(windows_map)
    remaining = [wid for wid in geometry_order if wid not in saved]

    order = saved + remaining
    state[space_id] = order
    return order


def command_order(state: Dict[str, List[str]]) -> int:
    space = parse_env_json('SPACE_JSON', {})
    windows = parse_env_json('WINDOWS_JSON', [])
    excluded_apps = {str(app) for app in parse_env_json('EXCLUDED_APPS_JSON', [])}
    exclude_floating = str(os.environ.get('EXCLUDE_FLOATING_JSON', 'false')).lower() == 'true'
    include_floating_apps = {str(app) for app in parse_env_json('INCLUDE_FLOATING_JSON', [])}

    windows_map = filter_windows(windows, excluded_apps, exclude_floating, include_floating_apps)
    if not windows_map:
        print('[]')
        return 0

    order_ids = build_order(space, windows_map, state)
    ordered_windows = [windows_map[wid] for wid in order_ids if wid in windows_map]
    save_state(state)
    json.dump(ordered_windows, sys.stdout)
    return 0


def command_sync(state: Dict[str, List[str]]) -> int:
    space = parse_env_json('SPACE_JSON', {})
    windows = parse_env_json('WINDOWS_JSON', [])
    excluded_apps = {str(app) for app in parse_env_json('EXCLUDED_APPS_JSON', [])}
    exclude_floating = str(os.environ.get('EXCLUDE_FLOATING_JSON', 'false')).lower() == 'true'
    include_floating_apps = {str(app) for app in parse_env_json('INCLUDE_FLOATING_JSON', [])}

    windows_map = filter_windows(windows, excluded_apps, exclude_floating, include_floating_apps)
    space_id = str(space.get('id'))
    order = geometry_sorted_ids(windows_map)
    state[space_id] = order
    save_state(state)
    reset_focus_state()
    return 0


def command_swap(state: Dict[str, List[str]], id_a: str, id_b: str) -> int:
    command_order(state)  # ensure state is current before swapping
    space = parse_env_json('SPACE_JSON', {})
    space_id = str(space.get('id'))
    order = state.get(space_id)
    if not order:
        return 0
    id_a = str(id_a)
    id_b = str(id_b)
    if id_a not in order or id_b not in order:
        return 0
    ia, ib = order.index(id_a), order.index(id_b)
    order[ia], order[ib] = order[ib], order[ia]
    state[space_id] = order
    save_state(state)
    reset_focus_state()
    return 0


def main() -> int:
    state = load_state()
    if len(sys.argv) < 2:
        return command_order(state)
    cmd = sys.argv[1]
    if cmd == 'order':
        return command_order(state)
    if cmd == 'sync':
        return command_sync(state)
    if cmd == 'swap' and len(sys.argv) >= 4:
        return command_swap(state, sys.argv[2], sys.argv[3])
    if cmd == 'clear':
        STATE_PATH.unlink(missing_ok=True)
        reset_focus_state()
        return 0
    return 0

if __name__ == '__main__':
    sys.exit(main())
