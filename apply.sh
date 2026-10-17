#!/bin/bash

# apply.sh <path> — apply a wallpaper with Omarchy's usual transition and
# re-derive the auto color theme from it (theme.sh → wallpaper-drop-auto).
#
#   video (mp4/mkv/webm/...) → played live via mpv on the Wayland desktop
#                              (no motion-wallpaper / tenzin needed)
#   image / gif              → omarchy-theme-bg-set
#
# Video playback uses mpv (already a hard dependency of Omarchy), so neither
# motion-wallpaper nor tenzin is required. The extracted frame is applied
# underneath as the static background while the video loops on top.
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

pidfile="$HOME/.local/state/omarchy/wallpaper-drop-mpv.pid"

kill_mpv() {
  if [[ -f $pidfile ]]; then
    kill "$(cat "$pidfile")" 2>/dev/null || true
    rm -f "$pidfile"
  fi
}

case ${path,,} in
  *.mp4|*.mkv|*.webm|*.mov|*.m4v|*.avi|*.mpeg|*.mpg)
    # Stop any previously running video, then play the new clip live via mpv
    # on the Wayland desktop. mpv loops, muted, no decorations.
    kill_mpv
    mpv --wayland --fullscreen --loop-file=inf --no-osc --no-border \
        --mute=yes --screen=0 "$path" &
    echo $! > "$pidfile"
    disown
    # Theme colors come from a frame; that frame is also the static
    # background under the video.
    frame=$("$plugin_dir/theme.sh" "$path" 2>/dev/null || true)
    if [[ -n $frame && -f $frame ]]; then
      omarchy-theme-bg-set "$frame" >/dev/null
    fi
    exit 0
    ;;
esac

# Static wallpaper: stop any video, then apply the image.
kill_mpv
omarchy-theme-bg-set "$path" >/dev/null
"$plugin_dir/theme.sh" "$path" >/dev/null 2>&1 || true
