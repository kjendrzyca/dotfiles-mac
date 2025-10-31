# Repository Guidelines

## Project Structure & Module Organization
The root `sketchybarrc` orchestrates bar setup, event subscriptions, and initial triggers. Active scripts live under `plugins/`; `windows.sh` rebuilds the equal-width window items and `focus_window.sh` handles index- and direction-based focus changes. Keep `*_bak` artifacts for reference only, and avoid committing `plugins/debug.log` or ad-hoc backups.

## Build, Test, and Development Commands
Run `sketchybar --reload` after config or script edits to apply changes. Use `sketchybar --trigger window_list_update` to regenerate items without restarting the bar. For data inspection, `yabai -m query --windows --space | jq 'sort_by(.app, .title)'` mirrors the ordering that `windows.sh` expects.

## Coding Style & Naming Conventions
Shell scripts use POSIX `sh`; prefer portable syntax, quoted variables, and four-space indentation within blocks. Represent constants in uppercase (`TEAL_COLOR`) and keep descriptive labels (`window_1`, `window_manager`) consistent with existing patterns. Place reusable helpers in `plugins/` and reference them via `$HOME/.config/sketchybar/...` so absolute paths remain stable.

## Testing Guidelines
No automated suite exists—validate changes by triggering the bar and verifying window tiles update, highlight focus, and respect minimum widths. When adjusting focus logic, test both numeric clicks and `prev/next` navigation. Capture screenshots of the bar before and after large UI tweaks to document visual regressions.

## Commit & Pull Request Guidelines
Use imperative, 50-character-or-fewer commit subjects (e.g., `Refine window width floor`) and detail motivation plus manual verification in the body. Group related config and plugin edits in one commit to keep history reviewable. Pull requests should link any tracking issues, describe macOS and SketchyBar versions tested, and attach visuals when the bar appearance changes.

## Dependencies & Configuration Tips
Ensure `/opt/homebrew/bin` remains on PATH so `yabai`, `jq`, and `sketchybar` resolve for scripts. Keep focus shortcuts in sync with `focus_window.sh`; update both the script and documentation if bindings change. When experimenting, duplicate scripts with a `.bak` suffix locally, but strip them before opening a PR.
