# AeroSpace + SketchyBar Overview

- **Renderer script:** `aerospace_windows.sh` keeps persistent `window_<window-id>` items. Each run queries `aerospace list-windows --workspace focused --json`, resizes items to fill the monitor width, updates labels/backgrounds in place, and drives focus with `aerospace focus --window-id …`.
- **Stable ordering:** After refreshing item properties, the script calls `sketchybar --reorder` with the AeroSpace window order so swaps only move the affected items without flashing the bar.
- **Helper binary:** `bin/monitor-width` (Swift) returns the NSScreen width for the focused monitor. The renderer uses it to size items across the bar.
- **Event setup:** `sketchybarrc` registers `aerospace_windows_update` and `aerospace_workspace_update`, and a hidden `aerospace_listener` item runs the renderer on startup, focus changes, and workspace changes.
- **Custom AeroSpace build:** We run a fork that outputs windows in DFS order (see `~/github/AeroSpace` and `~/github/AeroSpace/.debug`). Point SketchyBar at the new CLI with:
  ```bash
  launchctl setenv AEROSPACE_BIN ~/github/AeroSpace/.debug/aerospace
  sketchybar --reload
  ```
  Remove the override later with `launchctl unsetenv AEROSPACE_BIN`.
- **Bar refresh triggers:** AeroSpace keybinds for DFS focus and swap append `exec-and-forget /opt/homebrew/bin/sketchybar --trigger aerospace_windows_update` so the bar stays in sync immediately.

Run `sketchybar --trigger aerospace_windows_update` to force a redraw, or `AEROSPACE_BIN=… ~/.config/sketchybar/aerospace_windows.sh` for debugging.
