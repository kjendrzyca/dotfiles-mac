# Repository Guidelines

## Project Structure & Module Organization
`sketchybarrc` is the only orchestrator. It wires AeroSpace-triggered events (`aerospace_windows_update`, `aerospace_workspace_update`) to a hidden listener that executes `aerospace_windows.sh`. The `bin/monitor-width` Swift helper returns the current monitor width so `aerospace_windows.sh` can size items evenly. No plugin directory or state files remain.

## Build, Test, and Development Commands
Reload after edits with `sketchybar --reload`. To refresh the window list without restarting, call `sketchybar --trigger aerospace_windows_update`. For debugging, run the renderer directly: `AEROSPACE_BIN=/opt/homebrew/bin/aerospace ~/.config/sketchybar/aerospace_windows.sh`.

## Coding Style & Naming Conventions
Scripts use Bash with `set -euo pipefail`. Constants stay capitalised (`TEAL_COLOR`), and window items follow the `window_<index>` naming that matches keyboard shortcuts. Hardcode `/opt/homebrew/bin` for AeroSpace and jq to avoid PATH surprises.

## Testing Guidelines
After tweaking the renderer, toggle focus and workspace changes to ensure AeroSpace hooks fire and the bar redraws. Validate click-to-focus and keyboard reordering shortcuts (`swap dfs-*`) still update highlighting. Spot-check window widths on single- and multi-monitor setups.

## Commit & Pull Request Guidelines
Prefer single-purpose commits (e.g. “Adjust SketchyBar window width floor”). Document which AeroSpace commands were exercised during testing and note macOS version. Attach screenshots when adjusting colours or spacing.

## Dependencies & Configuration Tips
Requirements: `aerospace`, `sketchybar`, and `jq` under `/opt/homebrew/bin`. Ensure AeroSpace hooks (`on-focus-changed`, `exec-on-workspace-change`) remain in sync with event names expected here; mismatches will silently stop bar updates.
