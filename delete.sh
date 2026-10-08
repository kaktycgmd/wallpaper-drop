#!/bin/bash

# omarchy:summary=Delete a wallpaper from the drop folder
# omarchy:args=<path-in-drop-dir>
#
# delete.sh <path> — remove a file, but only one that lives inside the drop
# folder, and never the wallpaper the desktop currently shows.
#
# Exit codes: 0 deleted, 1 bad path, 3 current wallpaper (refused).

dir=${OMARCHY_WALLPAPER_DROP_DIR:-$HOME/.config/omarchy/backgrounds/wallpaper-drop}
path=${1:-}
[[ -n $path ]] || exit 1

real=$(realpath -e -- "$path" 2>/dev/null) || exit 1
reald=$(realpath -e -- "$dir" 2>/dev/null) || exit 1
# Containment: the target must be a file strictly inside the drop folder.
[[ $real == "$reald"/* && $real != "$reald" && -f $real ]] || exit 1

current=$(readlink -f "$HOME/.local/state/omarchy/current/background" 2>/dev/null || true)
if [[ -n $current && $real == "$current" ]]; then
  echo "active"
  exit 3
fi

rm -f -- "$real"
