#!/usr/bin/env python3
"""Build the app icon from the source artwork (design/icon-source.png).

Apple wants a 1024x1024, opaque, sRGB PNG with no alpha channel and no rounded
corners of its own — iOS applies its own mask. Because that mask cuts the
corners, artwork must not run to the canvas edge, so the source is scaled to
CONTENT_WIDTH of the canvas and centred on the art's own black.

    python3 design/appicon_from_art.py

Writes app/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (shipped
icon) and .../AppIconPreview.imageset/AppIconPreview.png (the copy the Settings
header draws, which Image("AppIcon") cannot load on iOS).
"""
import os
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "app", "Resources", "Assets.xcassets")
SRC = os.path.join(HERE, "icon-source.png")
S = 1024
CONTENT_WIDTH = 0.86       # widest content span, as a fraction of the canvas
BACKGROUND = (0, 0, 0)     # matches the artwork's own field
INK = 28                   # luma above this counts as artwork, not background


def content_bbox(rgb):
    """Bounds of the visible artwork, ignoring the black field around it."""
    return rgb.convert("L").point(lambda v: 255 if v > INK else 0).getbbox()


def build():
    src = Image.open(SRC).convert("RGB")          # drops any alpha channel
    bb = content_bbox(src)
    scale = (CONTENT_WIDTH * S) / (bb[2] - bb[0])
    scaled = src.resize((round(src.width * scale), round(src.height * scale)), Image.LANCZOS)

    # Centre the artwork itself, not the source canvas: the art sits high in it.
    cx = ((bb[0] + bb[2]) / 2) * scale
    cy = ((bb[1] + bb[3]) / 2) * scale
    canvas = Image.new("RGB", (S, S), BACKGROUND)
    canvas.paste(scaled, (round(S / 2 - cx), round(S / 2 - cy)))
    return canvas


if __name__ == "__main__":
    icon = build()
    out = os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon-1024.png")
    preview = os.path.join(ASSETS, "AppIconPreview.imageset", "AppIconPreview.png")
    icon.save(out)
    icon.resize((256, 256), Image.LANCZOS).save(preview)
    bb = content_bbox(icon)
    print(f"wrote {os.path.relpath(out)} and {os.path.relpath(preview)}")
    print(f"content margins L/T/R/B: {bb[0]}, {bb[1]}, {S-bb[2]}, {S-bb[3]}")
