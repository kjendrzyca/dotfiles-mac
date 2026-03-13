# macOS Window & Bar Config

This repository captures the parts of the macOS tiling workflow that need to live in version control: AeroSpace for window management, SketchyBar for a live window list on the menu bar, and Kitty for a terminal profile that visually matches the layout. Everything else in `~/.config` stays ignored on purpose.

## Quick Start

- Install the required apps (see each section).
- Install the free pre-commit guard for secret scanning: `brew install pre-commit`, then `pre-commit install` inside this repo.
- Review the configuration notes and adapt the tracked files (`aerospace/`, `sketchybar/`, `kitty/`, `karabiner/karabiner.json`) as inspiration for your own setup.
- Reload AeroSpace (`aerospace reload`) and SketchyBar (`sketchybar --reload`) whenever you copy changes into place.
- Run `pre-commit run --all-files` after enabling it to scan the current tracked files once.

---

## Karabiner-Elements

Karabiner-Elements handles the system-level remaps that unlock a Hyper key layer and normalize modifier layouts across keyboards, feeding the keybindings used in the AeroSpace and SketchyBar configs.

### Setup Requires

- `brew install --cask karabiner-elements` ([GitHub](https://github.com/pqrs-org/Karabiner-Elements))
- Enable Karabiner-Elements in System Settings ▸ Privacy & Security ▸ Input Monitoring and Accessibility
- Use `karabiner/karabiner.json` as the template for `~/.config/karabiner/karabiner.json`; Karabiner’s automatic backups remain untracked in `karabiner/automatic_backups/`

### Configuration Highlights

- Caps Lock becomes a Hyper layer that emits all four modifiers (`⌘⌃⌥⇧`) at once; AeroSpace leans on this combo for DFS navigation (`cmd-alt-ctrl-shift-'` etc.), and SketchyBar binds the same layer for bar triggers.
- `Hyper+Left/Right` remap to `⌃PageUp/PageDown`, providing a consistent previous/next tab shortcut across browsers and editors.
- Device-specific swaps flip the `⌘`/`⌥` positions on ANSI/ISO boards so physical legends line up with macOS defaults, while turning the right Command key into right Option preserves Polish diacritics (e.g. `⌥`+a → ą) on external layouts.
- Function key overrides map `F5/F6` to keyboard backlight controls to mirror Apple laptops.

---

## AeroSpace Tiling Window Manager

AeroSpace supplies deterministic tiling and depth-first window ordering on macOS, which keeps the bar integration and keyboard workflows predictable.

### Setup Requires

- `brew install --cask nikitabobko/tap/aerospace` ([GitHub](https://github.com/nikitabobko/AeroSpace))
- Optional but used by this setup: `brew install borders` for [JankyBorders](https://github.com/FelixKratz/JankyBorders)
- Grant AeroSpace Accessibility control (System Settings ▸ Privacy & Security ▸ Accessibility)
- Use `aerospace/aerospace.toml` as the reference for your `~/.config/aerospace/` configuration.

### Configuration Highlights

- `after-startup-command` ensures JankyBorders is running via `aerospace/start-borders.sh`, warms SketchyBar, triggers an initial full window refresh, and runs `sticky-overlays.sh` once at startup.
- `on-focus-changed` sends a lightweight `sketchybar --trigger aerospace_windows_update KIND=focus`, while `exec-on-workspace-change` forwards `FOCUSED` / `PREV` workspace IDs through `aerospace_workspace_update` and re-runs `sticky-overlays.sh`.
- `aerospace/overlay-windows.json` is the single source of truth for overlay windows. `Wispr Flow | Status` is marked `sticky`, `Scratchpad` is hidden from the bar and DFS navigation, and all consumers reuse the same rules.
- Layout reserves SketchyBar’s space and leaves room for [JankyBorders](https://github.com/Fedjmike/JankyBorders) outlines: inner gaps 2 px feed the border renderer, top outer gap 16 px clears the bar.
- DFS bindings: `cmd-alt-ctrl-shift-'` / `cmd-alt-ctrl-shift-;` cycle focus, `alt-shift-'` / `alt-shift-;` swap with the neighbouring DFS node. `aerospace/navigate.sh` filters overlay windows out of DFS focus/swap and triggers a full bar refresh after swaps.
- Workspace control: `alt-[0-9]` focuses slots 1–10, `alt-shift-[0-9]` moves the focused window and follows it.
- Launch chords: `cmd-alt-ctrl-shift-enter` opens Kitty, while `cmd-alt-ctrl-shift-f` opens Finder via `exec-and-forget` bindings.
- Maintenance chord `alt-shift-s` exposes recovery helpers (flatten layouts, toggle tiling) and exits with `esc`.
- `/opt/homebrew/bin` is exported via `[exec.env-vars]` so helper commands resolve correctly even when PATH differs.

### Overlay Windows + JankyBorders Helpers

- `aerospace/sticky-overlays.sh` keeps `sticky=true` overlay windows on the focused workspace using `overlay-windows.json` and `expect` (required because AeroSpace v0.20.0+ needs a TTY for `move-node-to-workspace` in non-interactive contexts).
- `aerospace/start-borders.sh` manages the `borders` process in two modes:
  - `~/.config/aerospace/start-borders.sh` ensures JankyBorders is running.
  - `~/.config/aerospace/start-borders.sh restart` restarts it cleanly after manual debugging or crashes.
- Detailed Wispr Flow notes live in `aerospace/WISPR_STATUS_RESEARCH.md`.

### Optional: Custom AeroSpace Build

The SketchyBar window list depends on the order returned by `aerospace list-windows` to be stable and to reflect the tiling tree (DFS order). Without that, bar item ordering “snaps” to a different sort order after swaps/focus changes, and the visual ordering no longer matches AeroSpace navigation.

Upstream has ongoing discussion/requests around exposing explicit DFS/tree ordering for `list-windows`:
- Issue `#491` (request for DFS-ordered window listing): https://github.com/nikitabobko/AeroSpace/issues/491
- PR `#1839` (attempt to add `--sort tree-order`): https://github.com/nikitabobko/AeroSpace/pull/1918
- Related SketchyBar integration discussion: https://github.com/nikitabobko/AeroSpace/issues/175

Until a supported ordering flag lands upstream, this setup uses a fork that removes the internal sorting so `list-windows` preserves the DFS order used by focus/swap commands.

1. Clone the fork into `~/github/AeroSpace` and build it via `./build-debug.sh`.
2. Stop the Homebrew service: `brew services stop aerospace`.
3. Launch the debug build: `open ~/github/AeroSpace/.debug/AeroSpaceApp`.
4. Point SketchyBar (and scripts) at the debug CLI:
   ```bash
   launchctl setenv AEROSPACE_BIN ~/github/AeroSpace/.debug/aerospace
   sketchybar --reload
   ```
5. Revert with `launchctl unsetenv AEROSPACE_BIN` and reload SketchyBar or restart AeroSpace.

---

## SketchyBar Custom Menu Bar

SketchyBar renders a scriptable menu bar. Paired with AeroSpace it provides a clickable list of windows that reflects the tiler’s ordering in real time.

### Setup Requires

- `brew tap FelixKratz/formulae`
- `brew install sketchybar jq` ([SketchyBar GitHub](https://github.com/FelixKratz/SketchyBar)) ([jq GitHub](https://github.com/jqlang/jq))
- Install Apple’s SF Pro fonts (`brew tap homebrew/cask-fonts && brew install font-sf-pro`) for consistent typography
- Optional: `brew install --cask sf-symbols` for icon experimentation
- Adapt the contents of `sketchybar/` when configuring `~/.config/sketchybar/`.

### Configuration Highlights

- `sketchybarrc` registers `aerospace_windows_update` / `aerospace_workspace_update`, restarts the long-lived Python service (`aerospace_windows_service.py`) with `nohup`, and points the hidden listener at a lightweight trigger script (`aerospace_windows_trigger.sh`).
- `aerospace_windows_trigger.sh` routes events into three message types for the socket service:
  - `KIND=focus` → fast focus-only highlight update.
  - `KIND=windows` / default → full window list refresh.
  - `aerospace_workspace_update` → workspace refresh path with a short reconciliation pass for AeroSpace’s transient workspace state.
- The Python service keeps window state in memory, filters overlays using `aerospace/overlay-windows.json`, caches monitor widths, updates only changed item properties, and removes stale bar items by comparing against SketchyBar’s current item list rather than only in-memory state.
- `aerospace_windows.sh` remains in the repo as a fallback reference but is no longer called by default.
- Colors, fonts, and padding stay tuned for a 16 px bar so the visuals still align with AeroSpace.
- Force a redraw any time with `sketchybar --trigger aerospace_windows_update KIND=windows` or `sketchybar --reload`; for focus-only debugging you can use `sketchybar --trigger aerospace_windows_update KIND=focus`.

### Restarting the AeroSpace Window Service

Switching AeroSpace binaries (for example, after rebuilding `~/github/AeroSpace/.debug`) requires restarting the Python renderer so it picks up the new CLI path:

1. Export the debug CLI for all login shells: `launchctl setenv AEROSPACE_BIN ~/github/AeroSpace/.debug/aerospace` (rerun this whenever the path changes). Verify with `launchctl getenv AEROSPACE_BIN` if needed.
2. Stop any stale renderer so the reload starts a fresh copy: `pkill -f aerospace_windows_service.py` (safe even if it is not running).
3. Reload SketchyBar to relaunch the daemon under the updated environment: `sketchybar --reload`.
4. Populate the bar immediately by triggering an update: `sketchybar --trigger aerospace_windows_update KIND=windows`.

`sketchybarrc` performs the same steps automatically on login, so running the commands above manually is only necessary after changing binaries or debugging the service.

### Monitor Width Helper

Compile the Swift helper once to restore proportional item widths:

```bash
cd ~/.config/sketchybar/bin
xcrun swiftc -O monitor-width.swift -o monitor-width
```

The compiled binary stays ignored by git; the renderer falls back gracefully if it is missing.

---

## Kitty Terminal

Kitty provides a GPU-accelerated terminal that fits neatly inside the tiling layout and matches the chosen colors.

### Setup Requires

- `brew install kitty` ([GitHub](https://github.com/kovidgoyal/kitty))
- Ensure fonts referenced by the config (Menlo base, Nerd Font variants if needed) are available
- Use `kitty/` as the template for your `~/.config/kitty/` setup.

### Configuration Highlights

- `kitty.conf` pulls in `OneDark.conf`, aligns padding with AeroSpace gaps, and keeps font sizing consistent with the SketchyBar labels.
