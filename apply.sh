#!/bin/bash

# apply.sh <path> — apply a wallpaper with Omarchy's usual transition and
# re-derive the auto color theme from it (theme.sh → wallpaper-drop-auto).
#
#   video (mp4/mkv/webm/...) → played live by wallpaper drop's own video layer
#                              (no motion-wallpaper / tenzin needed), with the
#                              extracted frame underneath as a fallback
#   image / gif              → stop the video layer, then omarchy-theme-bg-set
#
# The video layer is the plugin's own service (Service.qml, QtMultimedia), so
# neither motion-wallpaper nor tenzin is required. If QtMultimedia can't decode
# the clip, the extracted frame is applied as a static wallpaper instead.
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
    # Play live via wallpaper drop's own video service (QtMultimedia). No
    # motion-wallpaper / tenzin is needed. If the service isn't loaded or the
    # clip can't be decoded, fall back to the extracted frame below.
    played=0
    if omarchy-shell -q kaktyc.wallpaper-drop play "$path" >/dev/null 2>&1; then
      played=1
    fi
    # Theme colors come from a frame; that frame is also the static
    # background under the video — or the whole wallpaper when the video
    # layer couldn't take it.
    frame=$("$plugin_dir/theme.sh" "$path" 2>/dev/null || true)
    if [[ -n $frame && -f $frame ]]; then
      omarchy-theme-bg-set "$frame" >/dev/null
    elif (( !played )); then
      # No video layer and no frame could be extracted: nothing to show.
      exit 1
    fi
    exit 0
    ;;
esac

# Static wallpaper: stop the video layer so the static image shows through.
omarchy-shell -q kaktyc.wallpaper-drop stop >/dev/null
omarchy-theme-bg-set "$path" >/dev/null
"$plugin_dir/theme.sh" "$path" >/dev/null 2>&1 || true
