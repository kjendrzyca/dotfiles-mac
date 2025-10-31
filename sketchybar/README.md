# i3-like SketchyBar Configuration

This setup turns SketchyBar into an i3-style window list: every window on the active Space gets its own equally sized slice of the bar, with live updates driven by yabai.

## Features

### Ordered Equal-Spaced Window List
- Equal-width tiles across all visible windows on the current Space.
- Ordering mirrors yabai’s tiling stack via `plugins/window_order_state.py`; geometry is the baseline and manual swaps update the saved list.
- No alphabetical fallback—the list stays in tiling order on create/destroy/focus events.

### i3-inspired Layout
- Compact 15 pt bar, Menlo 10pt font, teal highlight for the focused window.
- Per-window items render as `[index] App: Title`, keeping backgrounds and clicks independent.
- Dynamic width per item with a minimum width cap for readability.

### Interaction & Navigation
- Click any entry to focus that window.
- Keyboard navigation (`focus_window.sh prev|next`) integrates with skhd (`hyper + ;/'`).
- Manual reordering (`shift + option + ;/'`) triggers a `windows_update` and updates the saved order.

### Integration & State Management
- Works with yabai’s query APIs while SIP remains enabled.
- `plugins/window_order_state.py` stores per-space order (`.window_order_state.json`) and clears per-space highlights when layouts change.
- `plugins/windows.sh` rebuilds equal-width items using the saved order; `plugins/focus_window.sh` handles clicks/keyboard focus with per-space highlight caching (`.window_focus_state`).
- `plugins/sync_window_order.sh` re-synchronises the saved order (wired to `hyper + \` in skhd).

## Files

- `sketchybarrc`: Bar styling and event wiring.
- `plugins/windows.sh`: Renders per-window SketchyBar items using the stored order.
- `plugins/focus_window.sh`: Click/keyboard navigation with per-space highlight storage.
- `plugins/window_order_state.py`: Python helper for ordering and highlight maintenance.
- `plugins/sync_window_order.sh`: Manual resync helper (optional shortcut/button).

This combination yields an equal-spaced, order-stable bar that reflects yasbai tiling accurately and plays nicely with skhd shortcuts.
