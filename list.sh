#!/bin/bash

# list.sh <drop-dir> — one "path<TAB>thumb<TAB>kind" row per wallpaper,
# newest first. kind is image | gif | video. Thumbnails live in
# ~/.cache/omarchy/wallpaper-drop keyed by path + size + mtime.

dir=${1:-}
[[ -n $dir && -d $dir ]] || exit 0

cache=${XDG_CACHE_HOME:-$HOME/.cache}/omarchy/wallpaper-drop
mkdir -p "$cache"

kind_of() {
  local name=${1,,}
  case $name in
    *.mp4|*.mkv|*.webm|*.mov|*.m4v|*.avi|*.mpeg|*.mpg) echo video ;;
    *.gif) echo gif ;;
    *) echo image ;;
  esac
}

thumb_for() {
  local file=$1 sig hash thumb tmp
  sig=$(stat -Lc '%s:%Y' -- "$file" 2>/dev/null) || return 1
  hash=$(printf '%s\t%s' "$file" "$sig" | md5sum | cut -d ' ' -f 1)
  thumb="$cache/$hash.jpg"

  if [[ ! -f $thumb ]]; then
    tmp="$thumb.tmp.$$"
    if ffmpegthumbnailer -i "$file" -o "$tmp" -s 400 -q 4 >/dev/null 2>&1 && [[ -s $tmp ]]; then
      mv -f -- "$tmp" "$thumb"
    else
      rm -f -- "$tmp"
      # Videos without a poster get no thumbnail; images fall back to
      # themselves so the grid still shows something.
      case ${file,,} in
        *.mp4|*.mkv|*.webm|*.mov|*.m4v|*.avi|*.mpeg|*.mpg) return 1 ;;
        *) printf '%s' "$file"; return 0 ;;
      esac
    fi
  fi
  printf '%s' "$thumb"
}

while IFS= read -r -d '' row; do
  file=${row#*$'\t'}
  [[ -f $file ]] || continue
  # Row output is line- and tab-delimited; skip names that would corrupt it.
  [[ $file == *$'\t'* || $file == *$'\n'* ]] && continue
  kind=$(kind_of "$file")
  thumb=$(thumb_for "$file") || continue
  printf '%s\t%s\t%s\n' "$file" "$thumb" "$kind"
done < <(find -L "$dir" -maxdepth 1 -type f \
  \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.bmp' \
     -o -iname '*.webp' -o -iname '*.gif' -o -iname '*.mp4' -o -iname '*.mkv' \
     -o -iname '*.webm' -o -iname '*.mov' -o -iname '*.m4v' \) \
  -printf '%T@\t%p\0' 2>/dev/null | sort -z -rn)
