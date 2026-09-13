#!/usr/bin/env python3
"""Build the app icon from source artwork in this folder.

Apple wants 1024x1024, opaque, sRGB, no alpha channel and no rounded corners of
its own — iOS applies its own mask, which cuts the corners, so nothing that
matters may sit in them.

Current artwork: the cleaned-up cover of Racunari no. 4 — the wireframe hand
reaching for a spark. Racunari ran Sezam, which is why it fits.

    python3 design/appicon_from_art.py

Writes app/Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png (shipped
icon) and .../AppIconPreview.imageset/AppIconPreview.png (the copy the Settings
header draws, since Image("AppIcon") cannot load the icon set on iOS).
"""
import os, functools
from PIL import Image, ImageChops, ImageEnhance, ImageFilter, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "app", "Resources", "Assets.xcassets")
S = 1024

SOURCE = "icon-source-racunari.jpg"
# Square crop: full source height, flush with the source's right edge, so the
# whole hand fits with the monitor chunk it reaches out of. Flush right matters:
# the spark sits in the source's own corner, and any leftward crop drags it into
# the icon's corner, where the mask cuts its core. Here the core clears by 20px.
CROP_ORIGIN = (110, 0)
CROP_SIDE = 1448
# Print scan, so: median kills the halftone dots, the downsample hides what is
# left, then a little sharpening and colour to undo the softening.
DENOISE, SHARPEN, COLOUR, CONTRAST = 3, (1.6, 60, 3), 1.12, 1.08
PHOSPHOR = True    # retro CRT pass; set False for the plain scan look

# Artwork that is already square and icon-shaped (e.g. the earlier phone drawing,
# icon-source.png) wants no crop — set CROP_SIDE = None and it is scaled to
# CONTENT_WIDTH of the canvas and centred on its own background instead.
CONTENT_WIDTH, INK = 0.86, 28


def clean(im):
    im = im.filter(ImageFilter.MedianFilter(DENOISE))
    im = im.resize((S, S), Image.LANCZOS)
    im = im.filter(ImageFilter.UnsharpMask(radius=SHARPEN[0], percent=SHARPEN[1], threshold=SHARPEN[2]))
    im = ImageEnhance.Color(im).enhance(COLOUR)
    return ImageEnhance.Contrast(im).enhance(CONTRAST)


# --- phosphor pass: black field, phosphor-green mesh; the monitor chunk and
# --- starburst (including cream rays) are kept exactly as scanned.
from PIL import Image, ImageChops, ImageFilter, ImageDraw
import functools

thr = lambda ch, t: ch.point(lambda v: 255 if v > t else 0)
lt  = lambda ch, t: ch.point(lambda v: 255 if v < t else 0)
AND = lambda *ms: functools.reduce(ImageChops.multiply, ms)
OR  = lambda *ms: functools.reduce(ImageChops.lighter, ms)
NOT = ImageChops.invert
PHOS = (70, 255, 120)     # phosphor green
CREAM = (255, 224, 150)   # the starburst ray the scan renders sage-green

def masks(im):
    S = im.size[0]
    R, G, B = im.split()
    _, Sa, V = im.convert("HSV").split()
    # The mesh must be green-DOMINANT. Without this the starburst's cream rays
    # (e.g. 168,163,116 — G-B of 47) get mistaken for mesh and recoloured green.
    green_dom = thr(ImageChops.subtract(G, R), 8)
    mesh = AND(green_dom, thr(ImageChops.subtract(G, B), 10), thr(V, 80))
    # Anything bright that is not green belongs to the rays / flare / beige and
    # is kept exactly as-is — including near-neutral cream, hence the R-B OR V test.
    warm = AND(NOT(green_dom), thr(V, 90), thr(ImageChops.subtract(R, B), 20))
    strip = Image.new("L", (S, S), 0)
    ImageDraw.Draw(strip).rectangle([0, 0, S, int(0.22 * S)], fill=255)
    grey = AND(NOT(green_dom), lt(Sa, 70), thr(V, 70), lt(V, 215), strip)
    protect = OR(warm, grey).filter(ImageFilter.MaxFilter(5))
    return mesh, protect

def render(im, levels=4, bloom_radius=11, bloom_strength=0.85):
    """Phosphor pass. The mesh becomes phosphor green on a black field; the
    monitor chunk and the starburst keep their scanned pixels."""
    S = im.size[0]
    G = im.split()[1]
    Lum = im.convert("L")
    mesh, protect = masks(im)

    # The hand is a dense field of mesh dots; the artwork's sage-green ray is a
    # thin line. Block occupancy separates them, so the ray is not made to glow
    # green with the hand.
    occ = mesh.resize((S // 32, S // 32), Image.BOX).resize((S, S), Image.BILINEAR)
    hand = occ.point(lambda v: 255 if v > 95 else 0).filter(ImageFilter.MaxFilter(31))
    mesh_only = AND(mesh, hand)
    stray = AND(mesh, NOT(hand))
    core = max(((Lum.getpixel((x, y)), x, y)                       # the flare
                for y in range(int(0.6*S), S, 2) for x in range(int(0.6*S), S, 2)))[1:]
    near = Image.new("L", (S, S), 0)
    ImageDraw.Draw(near).ellipse([core[0]-460, core[1]-460, core[0]+460, core[1]+460], fill=255)
    ray, far = AND(stray, near), AND(stray, NOT(near))

    def ramp(src, mask, colour, blur, strength, quantise, pct=(0.03, 0.97)):
        vals = sorted(v for v in ImageChops.multiply(src, mask).get_flattened_data() if v)
        lo, hi = vals[int(len(vals)*pct[0])], vals[int(len(vals)*pct[1])]
        I = ImageChops.multiply(src, mask).point(
            lambda v: 0 if v == 0 else max(0, min(255, int(255*(v-lo)/(hi-lo)))))
        if quantise:
            step = 255/(quantise-1)
            I = I.point(lambda v: int(round(v/step)*step))
        layer = Image.merge("RGB", tuple(I.point(lambda v, c=c: int(v*c/255)) for c in colour))
        glow = layer.filter(ImageFilter.GaussianBlur(blur))
        glow = Image.merge("RGB", tuple(ch.point(lambda v: int(v*strength)) for ch in glow.split()))
        return ImageChops.screen(layer, glow)

    out = Image.new("RGB", (S, S), (0, 0, 0))
    out.paste(ramp(G, mesh_only, PHOS, bloom_radius, bloom_strength, levels), (0, 0))
    out.paste(im, (0, 0), far.filter(ImageFilter.GaussianBlur(1)))                      # loose dots: as scanned
    out.paste(ramp(Lum, ray, CREAM, 7, 0.6, 0, (0.10, 0.95)), (0, 0),
              ray.filter(ImageFilter.GaussianBlur(1)))                                  # sage ray -> cream
    out.paste(im, (0, 0), protect.filter(ImageFilter.GaussianBlur(2)))                  # chunk + starburst
    return out


def content_bbox(rgb):
    return rgb.convert("L").point(lambda v: 255 if v > INK else 0).getbbox()


def build():
    src = Image.open(os.path.join(HERE, SOURCE)).convert("RGB")   # drops any alpha
    if CROP_SIDE:
        x, y = CROP_ORIGIN
        icon = clean(src.crop((x, y, x + CROP_SIDE, y + CROP_SIDE)))
        return render(icon) if PHOSPHOR else icon
    bb = content_bbox(src)
    scale = (CONTENT_WIDTH * S) / (bb[2] - bb[0])
    scaled = src.resize((round(src.width * scale), round(src.height * scale)), Image.LANCZOS)
    canvas = Image.new("RGB", (S, S), (0, 0, 0))
    canvas.paste(scaled, (round(S / 2 - (bb[0] + bb[2]) / 2 * scale),
                          round(S / 2 - (bb[1] + bb[3]) / 2 * scale)))
    return canvas


if __name__ == "__main__":
    icon = build()
    out = os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon-1024.png")
    preview = os.path.join(ASSETS, "AppIconPreview.imageset", "AppIconPreview.png")
    icon.save(out)
    icon.resize((256, 256), Image.LANCZOS).save(preview)
    print(f"wrote {os.path.relpath(out)} and {os.path.relpath(preview)} from {SOURCE}")
