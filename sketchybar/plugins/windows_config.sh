#!/usr/bin/env bash

# App names to exclude from the window list. Append entries as needed.
EXCLUDED_APPS=(

)

# When set to true, floating windows (like HUDs or popovers) won't appear in the bar.
EXCLUDE_FLOATING_WINDOWS=true

# Floating windows from these apps are allowed even when EXCLUDE_FLOATING_WINDOWS is true.
INCLUDE_FLOATING_APPS=(
    "Simulator"
    "Brain.fm"
)
