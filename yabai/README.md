# Yabai Setup Notes

This configuration assumes a few Homebrew packages are available:

- `yabai` – tiling window manager (running as a service with the scripting addition loaded).
- `sketchybar` – status bar that receives the signals configured in `yabairc`.
- `borders` – FelixKratz’ JankyBorders helper that draws the window borders.

Install everything with:

```sh
brew install koekeishiya/formulae/yabai
brew install FelixKratz/formulae/borders
brew install FelixKratz/formulae/sketchybar
```

After installation:

1. Run `sudo yabai --load-sa` once per macOS update to load the scripting addition (the config already does this on start, so keep the sudoers rule in place).  
2. Start the services you need, e.g. `brew services start yabai` and `brew services start sketchybar`.  
3. `borders` is launched directly from `~/.config/yabai/yabairc`, so no separate service config is required.
4. Reload the config after edits with:

```sh
yabai --restart-service && echo "Yabai restarted with new config"
```

With these components installed, launching Yabai will automatically trigger SketchyBar updates and spin up JankyBorders with the matching highlight color.
