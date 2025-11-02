# macOS Window & Bar Config

This repository captures the parts of the macOS tiling workflow that need to live in version control: AeroSpace for window management, SketchyBar for a live window list on the menu bar, and Kitty for a terminal profile that visually matches the layout. Everything else in `~/.config` stays ignored on purpose.

## Quick Start

- Install the required apps (see each section).
- Review the configuration notes and adapt the tracked files (`aerospace/`, `sketchybar/`, `kitty/`) as inspiration for your own setup.
- Reload AeroSpace (`aerospace reload`) and SketchyBar (`sketchybar --reload`) whenever you copy changes into place.

---

## AeroSpace Tiling Window Manager

AeroSpace supplies deterministic tiling and depth-first window ordering on macOS, which keeps the bar integration and keyboard workflows predictable.

### Setup Requires

- `brew install --cask nikitabobko/tap/aerospace` ([GitHub](https://github.com/nikitabobko/AeroSpace))
- Grant AeroSpace Accessibility control (System Settings ▸ Privacy & Security ▸ Accessibility)
- Use `aerospace/aerospace.toml` as the reference for your `~/.config/aerospace/` configuration.

### Configuration Highlights

- Hooks (`after-startup-command`, `on-focus-changed`, `exec-on-workspace-change`) trigger `sketchybar --trigger aerospace_windows_update`, keeping the menu bar in sync with focus and workspace changes. Workspace transitions forward both the previous and new IDs.
- Layout reserves SketchyBar’s space and leaves room for [JankyBorders](https://github.com/Fedjmike/JankyBorders) outlines: inner gaps 2 px feed the border renderer, top outer gap 16 px clears the bar.
- DFS bindings: `cmd-alt-ctrl-shift-'` / `cmd-alt-ctrl-shift-;` cycle focus, `alt-shift-'` / `alt-shift-;` swap with the neighbouring DFS node.
- Workspace control: `alt-[0-9]` focuses slots 1–10, `alt-shift-[0-9]` moves the focused window and follows it.
- Launch chords: `cmd-alt-ctrl-shift-enter` opens Kitty, while `cmd-alt-ctrl-shift-f` opens Finder via `exec-and-forget` bindings.
- Maintenance chord `alt-shift-s` exposes recovery helpers (flatten layouts, toggle tiling) and exits with `esc`.
- `/opt/homebrew/bin` is exported via `[exec.env-vars]` so helper commands resolve correctly even when PATH differs.

### Optional: Custom AeroSpace Build

The window renderer assumes a fork that preserves DFS ordering inside `list-windows`.

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

- `sketchybarrc` registers `aerospace_windows_update` and `aerospace_workspace_update`, and a hidden `aerospace_listener` item runs the renderer on startup and whenever AeroSpace rotates focus or workspaces.
- `aerospace_windows.sh` persists `window_<window-id>` items, pulls `aerospace list-windows --workspace focused --json`, resizes each item to consume its portion of the monitor width, and sets the click action to `aerospace focus --window-id …`.
- After every refresh the script issues `sketchybar --reorder` to keep the menu bar aligned with AeroSpace’s DFS order, so swaps never flash or recreate items.
- Colors, fonts, and padding are tuned for a 16 px tall bar, matching the reserved top gap in AeroSpace.
- Force a redraw any time with `sketchybar --trigger aerospace_windows_update` or `sketchybar --reload`.

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

---

Keep this README aligned with the tracked configs so anyone can recreate the window manager, menu bar, and terminal in one pass.
