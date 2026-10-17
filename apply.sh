#!/bin/bash

# apply.sh <path> — apply a wallpaper with Omarchy's usual transition and
# re-derive the auto color theme from it (theme.sh → wallpaper-drop-auto).
#
#   video (mp4/mkv/webm/...) → extracted frame applied as a static wallpaper
#   image / gif              → omarchy-theme-bg-set
#
# No motion-wallpaper / tenzin / or any other live-backend plugin is required:
# videos apply as a still frame extracted via theme.sh (ffmpeg).
#
# Static order matters: the background goes down first. A theme set swaps
# current/theme, so a symlink aimed into it would dangle — bg-set points the
# link at the real file before the swap, and OMARCHY_THEME_SKIP_BACKGROUND
# keeps theme.sh from touching it again.
#
# Exit codes: 0 applied, 1 bad path or could not apply.

path=${1:-}
[[ -n $path && -f $path ]] || exit 1
path=$(realpath -- "$path")
plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)

case ${path,,} in
  *.mp4|*.mkv|*.webm|*.mov|*.m4v|*.avi|*.mpeg|*.mpg)
    # Video has no dedicated live-backend dependency: extract a frame and
    # apply it as a static wallpaper. The frame is also used for the auto
    # color theme.
    frame=$("$plugin_dir/theme.sh" "$path" 2>/dev/null || true)
    if [[ -n $frame && -f $frame ]]; then
      omarchy-theme-bg-set "$frame" >/dev/null
      exit 0
    fi
    # No frame could be extracted: nothing to show.
    exit 1
    ;;
esac

# Static wallpaper.
omarchy-theme-bg-set "$path" >/dev/null
"$plugin_dir/theme.sh" "$path" >/dev/null 2>&1 || true
