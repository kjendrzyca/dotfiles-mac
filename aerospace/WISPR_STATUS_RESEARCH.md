# Wispr Flow "Status" Overlay + AeroSpace: Research Notes

This document captures the full context of the Wispr Flow overlay work so a future agent can continue debugging / improving it.

## Goal

- Keep Wispr Flow "Status" overlay (the recording indicator window) from interfering with normal window management:
  - Should NOT appear in SketchyBar window list.
  - Should NOT be reachable via DFS focus cycling.
  - Should NOT get JankyBorders.
  - Should be floating.
- Keep Wispr Flow "Hub" window fully normal/managed.
- Prefer a single source of truth for "overlay window" filtering across components.

## Environment / Constraints

- Use the user's custom AeroSpace fork binary (NOT brew):
  - Always resolve via `launchctl getenv AEROSPACE_BIN`.
  - Do NOT kill/restart AeroSpace arbitrarily.
- AeroSpace v0.20.0+ requires a TTY for some commands when run from hooks/non-interactive:
  - Workaround used: `expect -c "spawn ...; expect eof"`.
- AeroSpace upstream still lacks `list-windows --sort-by dfs-index` (user's fork provides needed behavior elsewhere).
- macOS: tested on 15.7.1 (from `debug-windows` output).

## Wispr Flow Window Model (Key Findings)

- Wispr Flow has two windows under the same bundle id `com.electron.wispr-flow`:
  - Main window: title `Hub`.
  - Overlay: title `Status`.
- The overlay shows up in AeroSpace as a dialog-like accessibility window:
  - `AXSubrole: AXDialog`.
  - `Aero.AxUiElementWindowType: dialog`.

This is important because dialog/overlay windows are more likely to be clamped/reset by macOS if their frame becomes invalid or offscreen.

## Shared Overlay Rules

Single source of truth lives here:

- `~/.config/aerospace/overlay-windows.json`

Current format:

```json
[
  { "app-name": "Wispr Flow", "window-title": "Status", "sticky": true },
  { "app-name": "Scratchpad", "sticky": false }
]
```

- `sticky: true` means: we try to keep the window on the currently focused AeroSpace workspace.
- Consumers:
  - AeroSpace scripts (DFS navigation + sticky overlays)
  - SketchyBar Python renderer filtering

## AeroSpace Config Changes

File:

- `~/.config/aerospace/aerospace.toml`

Highlights:

- `on-window-detected` for Wispr Status:
  - Match `if.app-id = 'com.electron.wispr-flow'` + `if.window-title-regex-substring = 'Status'`
  - Run: `layout floating`
- Sticky overlay behavior is driven by a script:
  - `after-startup-command` runs `sticky-overlays.sh` once on startup.
  - `on-focus-changed` runs `sticky-overlays.sh` (to recover when overlay jumps workspaces).
  - `exec-on-workspace-change` also runs `sticky-overlays.sh`.

Important limitation discovered:

- `on-window-detected` only supports a limited command set (currently `layout floating|tiling` and `move-node-to-workspace`).
  - You cannot run `exec-and-forget` from `on-window-detected`.

## Sticky Overlay Script

File:

- `~/.config/aerospace/sticky-overlays.sh`

Behavior:

- Reads `overlay-windows.json` and selects only rules with `sticky=true`.
- Finds matching windows using `aerospace list-windows --all --json` and jq.
- Moves those windows to the focused workspace.
- Uses `expect` to satisfy AeroSpace TTY requirements.
- Uses a lock dir (`/tmp/aerospace_sticky_overlays.lock`) to avoid overlapping runs.

Bug fixed:

- An earlier version used `declare -A` (bash associative arrays) which fails on macOS default bash 3.2.
  - Result: the script crashed and overlays were not moved, causing the overlay to "disappear".
  - Current script avoids associative arrays.

Logs:

- Unexpected move errors (excluding no-ops) are appended to:
  - `/tmp/aerospace_sticky_overlays.log`

## DFS Navigation / Swap Filtering

File:

- `~/.config/aerospace/navigate.sh`

What it does:

- Implements overlay-aware DFS focus/swap:
  - `focus-next`, `focus-prev`, `swap-next`, `swap-prev`
- Skips windows matching `overlay-windows.json`.
- For swap:
  - `swap` cannot target a specific window id.
  - Script computes the number of raw `swap dfs-next/dfs-prev` steps required and executes them.

SketchyBar refresh after swap:

- `exec-and-forget` bindings caused a race (trigger fired before swap finished).
- Fix: trigger SketchyBar update inside `navigate.sh` after swap completes.

## SketchyBar Window Renderer

Python service file:

- `~/.config/sketchybar/aerospace_windows_service.py`

Changes:

- Loads overlay ignore rules from `~/.config/aerospace/overlay-windows.json`.
- Adds a delayed refresh (0.2s) after each update to address close-lag:
  - On close, `on-focus-changed` fires and highlight updates, but `list-windows` can lag and still list the closed window.
  - Service schedules a second check; if the window order changed, it re-renders.

Startup issue (fixed):

- `brew services` runs SketchyBar with restricted PATH.
- `sketchybarrc` now starts the python service using `/opt/homebrew/bin/python3` plus `nohup` + `disown` so it survives script exit.

Trigger path:

- `~/.config/sketchybar/aerospace_windows_trigger.sh` sends UDP messages to the python service socket.

## The Wispr "Status" Disappearing Problem (Root Cause)

Symptom:

- Wispr Status overlay sometimes appears to disappear even though Wispr keeps running.

What we observed:

1) Sometimes the overlay actually moves to a non-visible workspace:
   - Example output:

   ```
   152667 | Wispr Flow | Status | ws=2 vis=false focused=false
   ```

   That makes it invisible by design.

2) More importantly, it can be on the correct visible workspace but physically offscreen:
   - Example ("bad" state):

   ```
   AXFrame: x=1727 y=1089 w=440 h=300
   screen bounds: 0,0,1728,1117
   ```

   This means only ~1px by ~28px can be visible; visually it looks gone.

Why it happens:

- AeroSpace emulates workspaces by moving windows offscreen for non-visible workspaces.
- If Wispr Status window ever becomes part of a non-visible workspace, it will be moved offscreen (usually near a corner).
- When brought back, Wispr/macOS does not always restore the bottom-center position.
  - Being `AXDialog` increases the chance of clamping/fallback placement.

Confirmed recovery behavior:

- Toggling `layout tiling` -> `layout floating` for the Status window forces a re-placement, but it resets to near top-left:
  - Example after toggle: `AXFrame x=1 y=54 ...`.

## Manual Recovery Commands

Find current Status window id:

```sh
AERO=$(launchctl getenv AEROSPACE_BIN)
$AERO list-windows --all --format '%{window-id} | %{app-name} | %{window-title} | ws=%{workspace} vis=%{workspace-is-visible} focused=%{workspace-is-focused}' | rg 'Wispr Flow'
```

Check geometry:

```sh
$AERO debug-windows --window-id <ID> | rg 'AXFrame|AXPosition|AXSize|AXMinimized|AXHidden|Aero\.workspace'
```

If offscreen, try forcing re-placement:

```sh
$AERO layout tiling --window-id <ID>
$AERO layout floating --window-id <ID>
```

Alternative quick test to "unhide" windows:

```sh
$AERO enable off
$AERO enable on
```

Restart Wispr Flow (used as a pragmatic workaround):

```sh
pkill -x "Wispr Flow" 2>/dev/null; sleep 0.5; open -b com.electron.wispr-flow
```

An alias was added to `~/.zshrc`:

```sh
alias wispr-restart='pkill -x "Wispr Flow" >/dev/null 2>&1; sleep 0.5; open -b com.electron.wispr-flow'
```

## What Still Needs a "Proper" Fix

The current setup reduces how often Status disappears (by keeping it on the focused workspace), but does not guarantee the overlay stays bottom-center.

Potential next directions (not implemented here):

- Detect offscreen frames and restore position (via accessibility API write to AXPosition).
  - Risky: Wispr dialog/overlay may fight you.
- Avoid AeroSpace hiding for this window entirely.
  - True "sticky" support is not built-in; current approach is a workaround.
- Identify the condition that makes Wispr Status get assigned to another workspace (ws changes) and prevent it.
  - Could be tied to monitor geometry changes (clamshell vs built-in), or overlay recreation timing.

## Recent Commits

- `40281a5` Keep Wispr Flow Status overlay on focused workspace
- `dccf5cd` Fix SketchyBar window list lag after close
