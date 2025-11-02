# AeroSpace + SketchyBar Overview

- **Renderer script:** `aerospace_windows.sh` rebuilds `window_*` items on each `aerospace_windows_update` trigger. It calls `aerospace list-windows --workspace focused --json`, divides the focused monitor width evenly, and issues `aerospace focus --window-id …` on click.
- **Helper binary:** `bin/monitor-width` (Swift) returns the NSScreen width for the focused monitor. The script uses it to size items across the bar.
- **Event setup:** `sketchybarrc` registers `aerospace_windows_update` and `aerospace_workspace_update`, then subscribes the hidden `aerospace_listener` item to run the renderer on every hook (startup, focus change, workspace change).
- **Custom AeroSpace build:** We run a fork that outputs windows in DFS order (see `~/github/AeroSpace` and `~/github/AeroSpace/.debug`). Point SketchyBar at the new CLI with:
  ```bash
  launchctl setenv AEROSPACE_BIN ~/github/AeroSpace/.debug/aerospace
  sketchybar --reload
  ```
  Remove the override later with `launchctl unsetenv AEROSPACE_BIN`.
- **Bar refresh triggers:** AeroSpace keybinds for DFS focus and swap append `exec-and-forget /opt/homebrew/bin/sketchybar --trigger aerospace_windows_update` so the bar stays in sync immediately.

Run `sketchybar --trigger aerospace_windows_update` to force a redraw, or `AEROSPACE_BIN=… ~/.config/sketchybar/aerospace_windows.sh` for debugging.
