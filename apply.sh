#!/bin/bash

# apply.sh <path> — apply a wallpaper with Omarchy's usual transition and
# re-derive the auto color theme from it (theme.sh → wallpaper-drop-auto).
#
#   video (mp4/mkv/webm/...) → motion-wallpaper if present, else tenzin
#   image / gif              → stop the video backends, then omarchy-theme-bg-set
#
# Static order matters: the background goes down first. A theme set swaps
# current/theme, so a symlink aimed into it would dangle — bg-set points the
# link at the real file before the swap, and OMARCHY_THEME_SKIP_BACKGROUND
# keeps theme.sh from touching it again.
#
# Exit codes: 0 applied, 1 bad path, 2 no video backend for a video.

path=${1:-}
[[ -n $path && -f $path ]] || exit 1
path=$(realpath -- "$path")
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

case ${path,,} in
  *.mp4|*.mkv|*.webm|*.mov|*.m4v|*.avi|*.mpeg|*.mpg)
    # Probe without -q: a quiet miss also exits 0, so it cannot tell
    # "target missing" from "target answered".
    if omarchy-shell motion-wallpaper status >/dev/null 2>&1; then
      # An explicit pick pins the clip: pin it by turning rotation off so
      # the user's rotation timer does not rotate the choice away.
      omarchy-shell -q motion-wallpaper setRotation off shuffle 0 >/dev/null
      omarchy-shell -q motion-wallpaper stop >/dev/null
      omarchy-shell -q motion-wallpaper play "$path" >/dev/null
      omarchy-shell -q tenzin.live-wallpaper stop >/dev/null
      # Theme colors come from a frame; that frame also becomes the static
      # background under the video.
      frame=$("$plugin_dir/theme.sh" "$path" 2>/dev/null || true)
      if [[ -n $frame && -f $frame ]]; then
        omarchy-theme-bg-set "$frame" >/dev/null
      fi
      exit 0
    fi
    if omarchy-shell tenzin.live-wallpaper status >/dev/null 2>&1; then
      omarchy-shell -q tenzin.live-wallpaper stop >/dev/null
      omarchy-shell -q tenzin.live-wallpaper play "$path" 600 >/dev/null
      frame=$("$plugin_dir/theme.sh" "$path" 2>/dev/null || true)
      if [[ -n $frame && -f $frame ]]; then
        omarchy-theme-bg-set "$frame" >/dev/null
      fi
      exit 0
    fi
    exit 2
    ;;
esac

# Static wallpaper: the video layers render above it, so stop them first.
omarchy-shell -q motion-wallpaper stop >/dev/null
omarchy-shell -q tenzin.live-wallpaper stop >/dev/null
omarchy-theme-bg-set "$path" >/dev/null
"$plugin_dir/theme.sh" "$path" >/dev/null 2>&1 || true
