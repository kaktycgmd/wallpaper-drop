#!/usr/bin/env python3
"""palette.py <image> <out-colors.toml> — derive an Omarchy colors.toml from an image."""

import collections
import colorsys
import sys

from PIL import Image

TARGET_HUES = {
    "red": 0.0,
    "orange": 27.0,
    "yellow": 52.0,
    "green": 135.0,
    "cyan": 185.0,
    "blue": 225.0,
    "magenta": 318.0,
}


def clamp(x, a=0.0, b=1.0):
    return a if x < a else (b if x > b else x)


def hls(r, g, b):
    h, l, s = colorsys.rgb_to_hls(r / 255.0, g / 255.0, b / 255.0)
    return h * 360.0, l, s


def rgb(h, l, s):
    r, g, b = colorsys.hls_to_rgb((h % 360.0) / 360.0, clamp(l), clamp(s))
    return int(r * 255.0 + 0.5), int(g * 255.0 + 0.5), int(b * 255.0 + 0.5)


def hx(t):
    return "#%02x%02x%02x" % t


def hue_dist(a, b):
    d = abs(a - b) % 360.0
    return min(d, 360.0 - d)


def load_entries(path):
    im = Image.open(path)
    try:
        im.seek(0)
    except EOFError:
        pass
    im = im.convert("RGB")
    im.thumbnail((160, 160))
    quantize = getattr(getattr(Image, "Quantize", None), "FASTOCTREE", 2)
    q = im.quantize(colors=20, method=quantize)
    pal = q.getpalette()
    data = q.get_flattened_data() if hasattr(q, "get_flattened_data") else q.getdata()
    counts = collections.Counter(data)
    total = sum(counts.values())
    entries = []
    for idx, n in counts.most_common():
        r, g, b = pal[3 * idx: 3 * idx + 3]
        entries.append((n / total, r, g, b))
    return entries


def main(path, out_path):
    entries = load_entries(path)
    if not entries:
        sys.exit("palette: no colors in image")

    # Decide the mode from perceptual (Rec.709) luminance, not HLS L: HLS
    # L = (max+min)/2 reads a saturated night-blue frame as ~0.52 and flips
    # a dark wallpaper to a light theme.
    mean_l = sum(w * (0.2126 * r + 0.7152 * g + 0.0722 * b) / 255.0 for w, r, g, b in entries)
    mean_s = sum(w * hls(r, g, b)[2] for w, r, g, b in entries)
    dark = mean_l <= 0.5

    dom_h, _, dom_s = hls(*entries[0][1:])

    # Background: dominant hue, forced legible lightness.
    bg_s = min(dom_s, 0.20) if dark else min(dom_s * 0.5, 0.12)
    if mean_s < 0.08:
        bg_s = 0.05 if dark else 0.04
    bg_l = 0.13 if dark else 0.97
    background = rgb(dom_h, bg_l, bg_s)

    # Accent: the most saturated color that covers a visible share of pixels.
    acc = max(
        (e for e in entries if e[0] >= 0.005),
        key=lambda e: hls(*e[1:])[2],
        default=None,
    )
    if acc is not None and hls(*acc[1:])[2] >= 0.22:
        acc_h = hls(*acc[1:])[0]
        acc_s = hls(*acc[1:])[2]
    else:
        acc_h, acc_s = 218.0, 0.85
    accent = rgb(acc_h, 0.70 if dark else 0.40, max(acc_s, 0.60 if dark else 0.50))

    # Semantic slots: reuse a palette color of a matching hue when one
    # exists, otherwise synthesize the canonical hue.
    sig = [e for e in entries if e[0] >= 0.004]

    def slot(hue):
        best, best_d = None, 41.0
        for w, r, g, b in sig:
            h, l, s = hls(r, g, b)
            if s < 0.10:
                continue
            d = hue_dist(h, hue)
            if d < best_d:
                best_d, best = d, (h, s)
        if best is not None:
            h, s = best
            s = max(s, 0.50)
        else:
            h, s = hue, 0.60
        return rgb(h, 0.68 if dark else 0.45, min(s, 0.92))

    red = slot(TARGET_HUES["red"])
    orange = slot(TARGET_HUES["orange"])
    yellow = slot(TARGET_HUES["yellow"])
    green = slot(TARGET_HUES["green"])
    cyan = slot(TARGET_HUES["cyan"])
    blue = slot(TARGET_HUES["blue"])
    magenta = slot(TARGET_HUES["magenta"])
    brown = rgb(hls(*orange)[0], 0.36, min(max(hls(*orange)[2], 0.25), 0.45))

    if dark:
        fg_src = hls(*max(entries, key=lambda e: hls(*e[1:])[1])[1:])
        foreground = rgb(fg_src[0], 0.86, clamp(max(fg_src[2] + 0.15, 0.30), 0.30, 0.60))
        dark_foreground = rgb(fg_src[0], 0.46, 0.22)
        light_foreground = rgb(fg_src[0], 0.76, 0.30)
        bg_dark = rgb(dom_h, 0.10, bg_s)
        bg_darker = rgb(dom_h, 0.075, bg_s)
        bg_lighter = rgb(dom_h, 0.26, min(bg_s + 0.05, 0.30))
        selection = rgb(dom_h, 0.30, min(bg_s + 0.10, 0.35))
        muted = rgb(dom_h, 0.37, min(bg_s + 0.08, 0.32))
    else:
        fg_src = hls(*min(entries, key=lambda e: hls(*e[1:])[1])[1:])
        foreground = rgb(fg_src[0], 0.15, clamp(max(fg_src[2], 0.45), 0.40, 0.80))
        dark_foreground = rgb(fg_src[0], 0.55, 0.10)
        light_foreground = rgb(fg_src[0], 0.27, 0.30)
        bg_dark = rgb(dom_h, 0.935, bg_s)
        bg_darker = rgb(dom_h, 0.89, bg_s)
        bg_lighter = rgb(dom_h, 0.90, bg_s)
        selection = rgb(dom_h, 0.80, min(bg_s + 0.06, 0.25))
        muted = rgb(dom_h, 0.71, min(bg_s + 0.05, 0.22))

    bright_foreground = foreground
    bright = {
        "red": red,
        "yellow": yellow,
        "green": green,
        "cyan": cyan,
        "blue": blue,
        "magenta": magenta,
    }

    lines = [
        'mode = "%s"' % ("dark" if dark else "light"),
        "",
        "accent = \"%s\"" % hx(accent),
        "selection = \"%s\"" % hx(selection),
        "muted = \"%s\"" % hx(muted),
        "",
        "background = \"%s\"" % hx(background),
        "dark_background = \"%s\"" % hx(bg_dark),
        "darker_background = \"%s\"" % hx(bg_darker),
        "lighter_background = \"%s\"" % hx(bg_lighter),
        "",
        "foreground = \"%s\"" % hx(foreground),
        "dark_foreground = \"%s\"" % hx(dark_foreground),
        "light_foreground = \"%s\"" % hx(light_foreground),
        "bright_foreground = \"%s\"" % hx(bright_foreground),
        "",
        "red = \"%s\"" % hx(red),
        "yellow = \"%s\"" % hx(yellow),
        "orange = \"%s\"" % hx(orange),
        "green = \"%s\"" % hx(green),
        "cyan = \"%s\"" % hx(cyan),
        "blue = \"%s\"" % hx(blue),
        "magenta = \"%s\"" % hx(magenta),
        "brown = \"%s\"" % hx(brown),
        "",
        "bright_red = \"%s\"" % hx(bright["red"]),
        "bright_yellow = \"%s\"" % hx(bright["yellow"]),
        "bright_green = \"%s\"" % hx(bright["green"]),
        "bright_cyan = \"%s\"" % hx(bright["cyan"]),
        "bright_blue = \"%s\"" % hx(bright["blue"]),
        "bright_magenta = \"%s\"" % hx(bright["magenta"]),
        "",
    ]
    with open(out_path, "w") as f:
        f.write("\n".join(lines))


if __name__ == "__main__":
    if len(sys.argv) != 3:
        sys.exit("usage: palette.py <image> <out-colors.toml>")
    main(sys.argv[1], sys.argv[2])
