#!/usr/bin/env python3
"""Generate the Sezam YU app icon: a phosphor terminal mid-connection.

    2400 B ?
    DIALING...
    >OK!
    >SEZAM_

Writes design/appicon.svg, the 1024 App Store icon and the 256px About-screen copy
straight into app/Resources/Assets.xcassets. Requires rsvg-convert and magick.

    python3 design/appicon_gen.py          # B (shipped): only the live SEZAM + cursor bright
    python3 design/appicon_gen.py A        # everything typed bright, modem text dim
    python3 design/appicon_gen.py C        # all bright
    python3 design/appicon_gen.py bubble   # the earlier ">SEZAM_" speech-bubble icon
"""
import os, subprocess, sys

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "app", "Resources", "Assets.xcassets")
S = 1024
GREEN = "#3DE07E"   # modem output, prompts, bubble outline (phosphor)
LIGHT = "#8CFFC0"   # the live line (bright phosphor)

# 5x7 bitmap glyphs in the spirit of a text-mode character ROM
FONT = {
    'S': [".####", "#....", "#....", ".###.", "....#", "....#", "####."],
    'E': ["#####", "#....", "#....", "####.", "#....", "#....", "#####"],
    'Z': ["#####", "....#", "...#.", "..#..", ".#...", "#....", "#####"],
    'A': [".###.", "#...#", "#...#", "#####", "#...#", "#...#", "#...#"],
    'M': ["#...#", "##.##", "#.#.#", "#...#", "#...#", "#...#", "#...#"],
    '>': ["#....", ".#...", "..#..", "...#.", "..#..", ".#...", "#...."],
    '2': [".###.", "#...#", "....#", "...#.", "..#..", ".#...", "#####"],
    '4': ["...#.", "..##.", ".#.#.", "#..#.", "#####", "...#.", "...#."],
    '0': [".###.", "#...#", "#..##", "#.#.#", "##..#", "#...#", ".###."],   # slashed zero
    'B': ["####.", "#...#", "#...#", "####.", "#...#", "#...#", "####."],
    '?': [".###.", "#...#", "....#", "...#.", "..#..", ".....", "..#.."],
    'O': [".###.", "#...#", "#...#", "#...#", "#...#", "#...#", ".###."],
    'K': ["#...#", "#..#.", "#.#..", "##...", "#.#..", "#..#.", "#...#"],
    'D': ["####.", "#...#", "#...#", "#...#", "#...#", "#...#", "####."],
    'I': [".###.", "..#..", "..#..", "..#..", "..#..", "..#..", ".###."],
    'L': ["#....", "#....", "#....", "#....", "#....", "#....", "#####"],
    'N': ["#...#", "#...#", "##..#", "#.#.#", "#..##", "#...#", "#...#"],
    'G': [".###.", "#...#", "#....", "#.###", "#...#", "#...#", ".###."],
    '.': [".....", ".....", ".....", ".....", ".....", ".##..", ".##.."],
    '!': ["..#..", "..#..", "..#..", "..#..", "..#..", ".....", "..#.."],
    ' ': ["....."] * 7,
}
CW, CH, GAP = 5, 7, 1          # glyph width, height, inter-glyph gap (font pixels)
LGAP = 6                       # blank font-pixel rows between lines

# (scale, [(text, role), ...]) per line; the block cursor follows the last line.
BIG = 1.4                      # the live >SEZAM line, relative to the modem lines
SCREEN = [
    (1.0, [("2400 B ?", "sys")]),
    (1.0, [("DIALING...", "sys")]),
    (1.0, [(">", "prompt"), ("OK!", "typed")]),
    (BIG, [(">", "prompt"), ("SEZAM", "typed")]),
]
LAST = len(SCREEN) - 1
COLOURS = {
    "A": lambda role, line: LIGHT if role == "typed" else GREEN,
    "B": lambda role, line: LIGHT if (role == "typed" and line == LAST) else GREEN,
    "C": lambda role, line: LIGHT,
}


def cells_for(screen):
    """(x, y, size, role, line) squares in base font-pixel units, plus block extent."""
    cells, width, y0 = [], 0, 0
    for li, (k, line) in enumerate(screen):
        x = 0
        for text, role in line:
            for ch in text:
                for r, row in enumerate(FONT[ch]):
                    for c, v in enumerate(row):
                        if v == "#":
                            cells.append((x + c * k, y0 + r * k, k, role, li))
                x += (CW + GAP) * k
        if li == len(screen) - 1:
            cells += [(x + c * k, y0 + r * k, k, "typed", li) for r in range(CH) for c in range(CW)]
            x += (CW + GAP) * k
        width = max(width, x - GAP * k)
        y0 += CH * k + LGAP
    return width, y0 - LGAP, cells


def rects(cells, ox, oy, px, colour):
    # +0.7 overlaps neighbouring squares so antialiasing leaves no hairline seams
    return "".join(
        f'<rect x="{ox+c*px:.2f}" y="{oy+r*px:.2f}" width="{k*px+0.7:.2f}" height="{k*px+0.7:.2f}" '
        f'fill="{colour(role, li)}"/>' for c, r, k, role, li in cells)


def crt(mark, vig_cy, glow, glow_opacity, blur, blur_opacity):
    """Dark phosphor tube: vignette, soft centre glow, bloom on the mark, scanlines."""
    return f'''<svg xmlns="http://www.w3.org/2000/svg" width="{S}" height="{S}" viewBox="0 0 {S} {S}">
<title>Sezam YU app icon</title>
<defs>
  <radialGradient id="vig" cx="0.5" cy="{vig_cy}" r="0.75">
    <stop offset="0" stop-color="#10301F"/><stop offset="0.55" stop-color="#071409"/><stop offset="1" stop-color="#010402"/>
  </radialGradient>
  <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
    <stop offset="0" stop-color="{LIGHT}" stop-opacity="{glow_opacity}"/><stop offset="1" stop-color="{LIGHT}" stop-opacity="0"/>
  </radialGradient>
  <filter id="blur" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="{blur}"/></filter>
  <pattern id="scan" width="{S}" height="14" patternUnits="userSpaceOnUse">
    <rect width="{S}" height="7" fill="#000000" opacity="0.22"/>
  </pattern>
  <g id="mark">{mark}</g>
</defs>
<rect width="{S}" height="{S}" fill="url(#vig)"/>
{glow}
<g filter="url(#blur)" opacity="{blur_opacity}"><use href="#mark"/></g>
<use href="#mark"/>
<rect width="{S}" height="{S}" fill="url(#scan)"/>
</svg>'''


def terminal(colour, mx=90, my=150):
    w, h, cells = cells_for(SCREEN)
    px = min((S - 2 * mx) / w, (S - 2 * my) / h)
    ox, oy = (S - w * px) / 2, (S - h * px) / 2
    return crt(rects(cells, ox, oy, px, colour), vig_cy=0.47,
               glow='<circle cx="512" cy="512" r="460" fill="url(#glow)"/>',
               glow_opacity=0.20, blur=14, blur_opacity=0.6)


def bubble(bw=852, hpad=34, vpad=62, stroke=56, tail=152):
    """The earlier icon: >SEZAM_ inside an outlined speech bubble."""
    w, _, cells = cells_for([(1.0, [(">", "prompt"), ("SEZAM", "typed")])])
    px = (bw - 2 * stroke - 2 * hpad) / w
    gh = CH * px
    bh = gh + 2 * vpad + 2 * stroke
    bx, by = (S - bw) / 2, (S - (bh + tail)) / 2
    ox, oy = bx + (bw - w * px) / 2, by + (bh - gh) / 2
    r_ = 60
    tx1, tx2, ty = bx + 150, bx + 330, by + bh + tail
    d = (f'M {bx+r_} {by} H {bx+bw-r_} A {r_} {r_} 0 0 1 {bx+bw} {by+r_} V {by+bh-r_} '
         f'A {r_} {r_} 0 0 1 {bx+bw-r_} {by+bh} H {tx2} L {tx1} {ty} L {tx1} {by+bh} '
         f'H {bx+r_} A {r_} {r_} 0 0 1 {bx} {by+bh-r_} V {by+r_} A {r_} {r_} 0 0 1 {bx+r_} {by} Z')
    mark = (f'<path d="{d}" fill="none" stroke="{GREEN}" stroke-width="{stroke}" stroke-linejoin="round"/>'
            + rects(cells, ox, oy, px, lambda role, li: GREEN if role == "prompt" else LIGHT))
    return crt(mark, vig_cy=0.42,
               glow='<circle cx="512" cy="500" r="440" fill="url(#glow)"/>',
               glow_opacity=0.26, blur=18, blur_opacity=0.5)


if __name__ == "__main__":
    variant = sys.argv[1] if len(sys.argv) > 1 else "B"
    svg = bubble() if variant == "bubble" else terminal(COLOURS[variant])
    svg_path = os.path.join(HERE, "appicon.svg")
    icon = os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon-1024.png")
    preview = os.path.join(ASSETS, "AppIconPreview.imageset", "AppIconPreview.png")
    raw = os.path.join(HERE, ".appicon-raw.png")
    open(svg_path, "w").write(svg)
    subprocess.run(["rsvg-convert", "-w", str(S), "-h", str(S), svg_path, "-o", raw], check=True)
    # App Store icons must be opaque: flatten onto black and drop the alpha channel.
    subprocess.run(["magick", raw, "-background", "black", "-alpha", "remove", "-alpha", "off",
                    "-colorspace", "sRGB", icon], check=True)
    subprocess.run(["magick", icon, "-resize", "256x256", "-colorspace", "sRGB", preview], check=True)
    os.remove(raw)
    print(f"variant {variant}: wrote {os.path.relpath(svg_path)}, {os.path.relpath(icon)}, {os.path.relpath(preview)}")
