# Wallpaper Drop

A drop-folder wallpaper picker for [Omarchy](https://omarchy.org/). Drag images, GIFs, and videos from your file manager into a compact grid panel next to the bar, preview them (GIFs and videos animate), and apply the one you like — each apply also generates a color theme from that wallpaper.

## Features

- **Drag & drop import** — drop files from any file manager onto the panel; they are copied into `~/.config/omarchy/backgrounds/wallpaper-drop/`.
- **Animated previews** — GIFs animate, videos play right in the grid.
- **One-key apply** — `Enter` applies the selection; images and GIFs go through Omarchy's wallpaper transition, videos pin into Motion Wallpaper (or Live Wallpaper as fallback).
- **Auto color theme** — every apply derives a theme from the wallpaper using [Aether](https://github.com/omacom/aether)'s color extractor (`aether --generate --no-apply`, dark by default) and activates it as the `wallpaper-drop-auto` theme. If `aether` is not installed, a built-in palette extractor is used instead. The background is applied before the theme so the link never dangles.
- **Delete** — `Del` or right-click a tile to remove the file (protected from deleting your current background).
- **Compact, non-blocking panel** — opens next to the bar, closes with `×` or `Esc`, never closes on outside clicks, and does not steal keyboard focus from the rest of your desktop.
- **Filter** — just type to filter by file name.

## Install

```bash
omarchy plugin add https://github.com/kaktycgmd/wallpaper-drop --enable
```

Open it from the **Wallpaper Drop** button on the right side of the bar.

## Remove

```bash
omarchy plugin remove kaktyc.wallpaper-drop
```

Removal uninstalls the plugin code only. Wallpapers already imported into the drop folder, the applied background, and the generated `wallpaper-drop-auto` theme are left untouched.

## Optional dependencies

| Dependency | Used for |
|---|---|
| `aether` | Color theme extraction (dark, from the wallpaper). Falls back to the built-in extractor. |
| `nosignal.motion-wallpaper` or `tenzin.live-wallpaper` | Playing video wallpapers. |
| `ffmpeg` | Extracting the theme frame from a video. |

## Requirements

Omarchy Quattro with the Quickshell-based shell (ships with current Omarchy).

## License

[MIT](LICENSE)
