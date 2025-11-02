# AeroSpace Configuration Overview

- **Hooks:** `after-startup-command`, `on-focus-changed`, and `exec-on-workspace-change` each trigger `sketchybar --trigger aerospace_windows_update` so the bar reflects workspace/window updates immediately. Workspace transitions also forward the previous and new workspace IDs.
- **Gaps:** Inner gaps set to 2 px with a 16 px top outer gap to reserve space for SketchyBar.
- **Navigation:** `cmd-alt-ctrl-shift-'` / `cmd-alt-ctrl-shift-;` cycle windows in depth-first order (`focus dfs-next|dfs-prev`).
- **Reordering:** `alt-shift-;` / `alt-shift-'` swap the focused window with its DFS neighbour using `swap dfs-prev|dfs-next`.
- **Workspace Control:** `alt-[0-9]` focuses workspace `1-10`; `alt-shift-[0-9]` moves the focused window there and follows it via `move-node-to-workspace` + `workspace`.
- **Launchers:** Hyper-style chords (`cmd-alt-ctrl-shift-enter/f`) open Kitty or Finder, handled directly by `exec-and-forget` bindings.
- **Service Mode:** `alt-shift-s` enters a maintenance mode with bindings such as `flatten-workspace-tree` and `layout floating tiling` for quick recovery tasks. Exit with `esc`.

The configuration expects AeroSpace and SketchyBar binaries under `/opt/homebrew/bin` and forwards that path explicitly inside the `[exec.env-vars]` block. Apply changes with `aerospace reload` or by restarting the service.

## Custom fork & SketchyBar integration

- **Forked build:** We use a fork of AeroSpace that removes the alphabetical sort inside `list-windows` so DFS order is preserved. The repo lives in `~/github/AeroSpace`; build it with `./build-debug.sh`.
- **Running the fork:** Quit the Homebrew service (`brew services stop aerospace`), launch the debug build via `open ~/github/AeroSpace/.debug/AeroSpaceApp`, and point SketchyBar at the new CLI:
  ```bash
  launchctl setenv AEROSPACE_BIN ~/github/AeroSpace/.debug/aerospace
  sketchybar --reload
  ```
  To revert later, run `launchctl unsetenv AEROSPACE_BIN` and reload SketchyBar.
- **Bar refresh triggers:** DFS focus (`cmd-alt-ctrl-shift-'` / `cmd-alt-ctrl-shift-;`) and swap bindings now append `sketchybar --trigger aerospace_windows_update` so the bar updates instantly. Mirror that trigger if you add new focus/swap bindings.
