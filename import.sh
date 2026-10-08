#!/bin/bash

# import.sh — copy wallpapers into the drop folder and print the final paths,
# one per line.
#
#   import.sh <file>...     copy the given files
#   import.sh --clipboard   copy what the clipboard points at (file URIs,
#                           plain paths, or a raw image payload)

dir=${OMARCHY_WALLPAPER_DROP_DIR:-$HOME/.config/omarchy/backgrounds/wallpaper-drop}
mkdir -p -- "$dir" || exit 1

ext_ok() {
  case ${1,,} in
    *.jpg|*.jpeg|*.png|*.bmp|*.webp|*.gif|*.mp4|*.mkv|*.webm|*.mov|*.m4v) return 0 ;;
    *) return 1 ;;
  esac
}

declare -a srcs=()
paste_png=""

if [[ ${1:-} == "--clipboard" ]]; then
  shift

  while IFS= read -r line; do
    [[ -n $line ]] || continue
    case $line in
      file://*)
        s=${line#file://}
        p=$(printf '%b' "${s//%/\\x}")
        ;;
      /*) p=$line ;;
      *) continue ;;
    esac
    srcs+=("$p")
  done < <(wl-paste --type text/uri-list 2>/dev/null || true)

  if (( ${#srcs[@]} == 0 )); then
    # No file references — an image copied as pixels still counts.
    tmp=$(mktemp --suffix=.png)
    if wl-paste --type image/png >"$tmp" 2>/dev/null && [[ -s $tmp ]]; then
      paste_png=$tmp
    else
      rm -f -- "$tmp"
      exit 0
    fi
  fi
else
  srcs=("$@")
fi

copied=0

if [[ -n $paste_png ]]; then
  target="$dir/Pasted $(date +%Y%m%d-%H%M%S).png"
  if mv -f -- "$paste_png" "$target" 2>/dev/null; then
    printf '%s\n' "$target"
    copied=1
  fi
fi

for src in "${srcs[@]}"; do
  [[ -f $src && -r $src ]] || continue
  ext_ok "$src" || continue

  base=$(basename -- "$src")
  stem=${base%.*}
  ext=${base##*.}

  # Already in the drop folder: nothing to copy, just report it.
  case $(realpath -m -- "$src") in
    "$(realpath -m -- "$dir")"/*)
      printf '%s\n' "$src"
      copied=1
      continue
      ;;
  esac

  target="$dir/$base"
  n=2
  while [[ -e $target ]]; do
    target="$dir/$stem ($n).$ext"
    n=$((n + 1))
  done

  if cp -- "$src" "$target" 2>/dev/null; then
    printf '%s\n' "$target"
    copied=1
  fi
done

exit $(( copied > 0 ? 0 : 1 ))
