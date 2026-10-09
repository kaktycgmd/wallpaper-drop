#!/bin/bash

# omarchy:summary=Derive and apply an auto color theme from a wallpaper
# omarchy:args=<path-to-image-or-video>
# omarchy:hidden=true
#
# theme.sh <path> — generate colors.toml from an image (or a frame of a
# video) into the wallpaper-drop-auto theme and apply it. The background
# link is never touched: apply.sh sets the wallpaper afterwards.
#
# Colors come from aether (--no-apply: colors only, no activation and no
# icon/editor side effects) — same extractor that produces the user's
# .aether-managed themes, dark by default. palette.py is the fallback.
#
# Prints the image the palette came from (the extracted frame for videos).

set -euo pipefail

# Extracted video frames can show private wallpapers, so keep the cache
# owner-only: umask 077 for new files and 0700 on the directory.
umask 077

src=${1:-}
[[ -n $src && -f $src ]] || { echo "usage: theme.sh <image-or-video>" >&2; exit 1; }
src=$(realpath -- "$src")

plugin_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
theme_name="wallpaper-drop-auto"
theme_dir="$HOME/.config/omarchy/themes/$theme_name"
mkdir -p "$theme_dir"
mkdir -p "$HOME/.cache/omarchy/wallpaper-drop"
chmod 700 "$HOME/.cache/omarchy/wallpaper-drop" 2>/dev/null || true

case ${src,,} in
  *.mp4|*.mkv|*.webm|*.mov|*.m4v|*.avi|*.mpeg|*.mpg)
    cache="$HOME/.cache/omarchy/wallpaper-drop"
    mkdir -p "$cache"
    key=$(printf '%s' "$src" | md5sum | cut -c1-16)
    frame="$cache/frame-$key.png"
    if [[ ! -f $frame ]]; then
      ffmpeg -y -loglevel error -ss 2 -i "$src" -frames:v 1 -an "$frame" 2>/dev/null ||
        ffmpeg -y -loglevel error -i "$src" -frames:v 1 -an "$frame" 2>/dev/null ||
        rm -f "$frame"
    fi
    [[ -f $frame ]] || exit 1
    src=$frame
    ;;
esac

log="$HOME/.cache/omarchy/wallpaper-drop/theme.log"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

if command -v aether >/dev/null 2>&1 &&
   aether --generate "$src" --no-apply --output "$tmp" >>"$log" 2>&1 &&
   [[ -f $tmp/colors.toml ]]; then
  cp "$tmp/colors.toml" "$theme_dir/colors.toml"
else
  python3 "$plugin_dir/palette.py" "$src" "$theme_dir/colors.toml"
fi
OMARCHY_THEME_SKIP_BACKGROUND=1 omarchy theme set "$theme_name" >>"$log" 2>&1
printf '%s\n' "$src"
