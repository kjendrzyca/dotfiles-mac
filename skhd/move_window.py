#!/usr/bin/env python3
"""Move the focused window between spaces while holding a simulated drag."""

import ctypes
import json
import subprocess
import sys
import time


CORE_GRAPHICS_PATH = (
    "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
)

core = ctypes.CDLL(CORE_GRAPHICS_PATH)


class CGPoint(ctypes.Structure):
    _fields_ = [("x", ctypes.c_double), ("y", ctypes.c_double)]


core.CGEventCreateMouseEvent.restype = ctypes.c_void_p
core.CGEventCreateMouseEvent.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint32,
    CGPoint,
    ctypes.c_uint32,
]
core.CGEventCreateKeyboardEvent.restype = ctypes.c_void_p
core.CGEventCreateKeyboardEvent.argtypes = [
    ctypes.c_void_p,
    ctypes.c_uint16,
    ctypes.c_bool,
]
core.CGEventSetFlags.argtypes = [ctypes.c_void_p, ctypes.c_uint64]
core.CGEventPost.argtypes = [ctypes.c_uint32, ctypes.c_void_p]
core.CFRelease.argtypes = [ctypes.c_void_p]
core.CGEventCreate.restype = ctypes.c_void_p
core.CGEventCreate.argtypes = [ctypes.c_void_p]
core.CGEventGetLocation.restype = CGPoint
core.CGEventGetLocation.argtypes = [ctypes.c_void_p]

KCG_EVENT_MOUSE_MOVED = 5
KCG_EVENT_LEFT_MOUSE_DOWN = 1
KCG_EVENT_LEFT_MOUSE_UP = 2
KCG_EVENT_LEFT_MOUSE_DRAGGED = 6
KCG_EVENT_FLAG_MASK_ALTERNATE = 1 << 19
KCG_HID_EVENT_TAP = 0
KCG_MOUSE_BUTTON_LEFT = 0


def run_yabai_query(args):
    return subprocess.check_output(["yabai", "-m", "query", *args])


def current_space_info():
    spaces = json.loads(run_yabai_query(["--spaces"]))
    for space in spaces:
        if space.get("has-focus"):
            return {"index": int(space["index"]), "display": int(space["display"])}
    raise RuntimeError("No focused space reported by yabai")


def focused_window():
    try:
        info = json.loads(run_yabai_query(["--windows", "--window"]))
    except subprocess.CalledProcessError:
        return None
    if not info or "frame" not in info:
        return None
    return info


def mouse_event(event_type, position):
    point = CGPoint(position[0], position[1])
    event = core.CGEventCreateMouseEvent(None, event_type, point, KCG_MOUSE_BUTTON_LEFT)
    core.CGEventPost(KCG_HID_EVENT_TAP, event)
    core.CFRelease(event)


def drag_nudge(current_pos, delta_x=8, steps=6, interval=0.04):
    target = [current_pos[0] + delta_x, current_pos[1]]
    for i in range(1, steps + 1):
        x = current_pos[0] + (target[0] - current_pos[0]) * i / steps
        mouse_event(KCG_EVENT_LEFT_MOUSE_DRAGGED, (x, current_pos[1]))
        time.sleep(interval)
    current_pos[0] = target[0]


def drag_pulse(position, cycles=1, amplitude=6, interval=0.05):
    for _ in range(cycles):
        mouse_event(KCG_EVENT_LEFT_MOUSE_DRAGGED, (position[0] + amplitude, position[1]))
        time.sleep(interval)
        mouse_event(KCG_EVENT_LEFT_MOUSE_DRAGGED, (position[0] - amplitude, position[1]))
        time.sleep(interval)
        mouse_event(KCG_EVENT_LEFT_MOUSE_DRAGGED, (position[0], position[1]))
        time.sleep(interval)


def key_press(keycode, modifiers):
    event_down = core.CGEventCreateKeyboardEvent(None, ctypes.c_uint16(keycode), True)
    core.CGEventSetFlags(event_down, ctypes.c_uint64(modifiers))
    core.CGEventPost(KCG_HID_EVENT_TAP, event_down)
    core.CFRelease(event_down)

    event_up = core.CGEventCreateKeyboardEvent(None, ctypes.c_uint16(keycode), False)
    core.CGEventSetFlags(event_up, ctypes.c_uint64(modifiers))
    core.CGEventPost(KCG_HID_EVENT_TAP, event_up)
    core.CFRelease(event_up)


def main():
    if len(sys.argv) != 3:
        raise SystemExit("usage: move_window.py <target-space> <focus-keycode>")

    target_space = int(sys.argv[1])
    focus_keycode = int(sys.argv[2])

    window = focused_window()
    if not window:
        return

    space_info = current_space_info()
    current_space = space_info["index"]
    step_delta = target_space - current_space
    if step_delta == 0:
        key_press(focus_keycode, KCG_EVENT_FLAG_MASK_ALTERNATE)
        return

    frame = window["frame"]
    center_x = frame["x"] + frame["w"] / 2
    center_y = frame["y"] + frame["h"] / 2

    title_region = min(max(frame["h"] * 0.05, 18), max(frame["h"] / 3, 1))
    drag_y = frame["y"] + title_region / 2
    if drag_y < frame["y"] or drag_y > frame["y"] + frame["h"]:
        drag_y = center_y

    traffic_offset = max(24, min(frame["w"] * 0.05, frame["w"] / 4))
    drag_x = frame["x"] + traffic_offset
    if drag_x > frame["x"] + frame["w"] - 20:
        drag_x = center_x

    drag_point = [drag_x, drag_y]

    current_event = core.CGEventCreate(None)
    current_loc = core.CGEventGetLocation(current_event)
    core.CFRelease(current_event)
    original_pos = (current_loc.x, current_loc.y)

    mouse_event(KCG_EVENT_MOUSE_MOVED, tuple(drag_point))
    time.sleep(0.04)
    mouse_event(KCG_EVENT_LEFT_MOUSE_DOWN, tuple(drag_point))
    time.sleep(0.06)
    drag_nudge(drag_point, delta_x=12, steps=6, interval=0.04)

    key_press(focus_keycode, KCG_EVENT_FLAG_MASK_ALTERNATE)

    start = time.time()
    while time.time() - start < 1.5:
        info = current_space_info()
        if info["index"] == target_space:
            break
        drag_pulse(drag_point, cycles=1, amplitude=4, interval=0.05)

    drag_pulse(drag_point, cycles=1, amplitude=3, interval=0.05)
    mouse_event(KCG_EVENT_LEFT_MOUSE_UP, tuple(drag_point))
    time.sleep(0.08)

    mouse_event(KCG_EVENT_MOUSE_MOVED, original_pos)


if __name__ == "__main__":
    main()
