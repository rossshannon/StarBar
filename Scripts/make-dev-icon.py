#!/usr/bin/env python3
"""Draw StarBar Dev's icon: StarBar's own, with a blue DEV ribbon across its top-right corner.

    python3 Scripts/make-dev-icon.py [--font PATH]

Reads every PNG in AppIcon.appiconset and writes the same names and Contents.json to
AppIconDev.appiconset beside it, which `./build.sh --dev` builds in (STARBAR_APP_ICON_dev in
the project). Run it again whenever the app icon changes. Needs Pillow (pip install Pillow).

The ribbon is drawn once on the largest image and scaled down for the others, so every size
is the same picture; at 16 and 32 pixels the word is too small to read and the blue corner is
what tells the two apps apart. Blue because the star has red, orange, yellow and green.
"""

import argparse
import json
import math
import shutil
from pathlib import Path

from PIL import Image, ImageChops, ImageDraw, ImageFilter, ImageFont

ASSETS = Path(__file__).resolve().parent.parent / "StarBar" / "Supporting Files" / "Assets.xcassets"
SOURCE = ASSETS / "AppIcon.appiconset"
TARGET = ASSETS / "AppIconDev.appiconset"

# Bold faces to try, first found wins: macOS's own, then common Linux ones
FONT_CANDIDATES = [
    "/System/Library/Fonts/SFNS.ttf",
    "/System/Library/Fonts/Supplemental/Arial Bold.ttf",
    "/usr/share/fonts/opentype/inter/Inter-Bold.otf",
    "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
]

RIBBON_TOP = (64, 140, 255)      # lighter blue along the ribbon's upper edge
RIBBON_BOTTOM = (16, 92, 222)    # deeper blue along its lower edge
TEXT = (255, 255, 255)


def load_font(path, size):
    font = ImageFont.truetype(path, size)
    try:
        # SF is a variable font; ask for its bold instance
        font.set_variation_by_name("Bold")
    except (OSError, ValueError, AttributeError):
        pass
    return font


def squircle_mask(icon):
    """The icon's rounded square, from its alpha: inside is opaque, the drop shadow is not."""
    return icon.getchannel("A").point(lambda v: 0 if v < 128 else min(255, (v - 128) * 2))


def ribbon(size, box, font_path):
    """The ribbon on its own, size by size pixels: a blue band across the top-right corner
    of box (left, top, right, bottom), with DEV along it."""
    left, top, right, bottom = box
    side = right - left
    # The band's centre line runs from the top edge to the right edge, this far from the corner
    reach = side * 0.42
    width = side * 0.14

    band = Image.new("L", (size, size), 0)
    draw = ImageDraw.Draw(band)
    # A long thin rectangle, centred on the corner's diagonal, rotated by 45 degrees
    cx, cy = right - reach / 2, top + reach / 2
    half_length, half_width = side, width / 2
    angle = math.radians(45)
    dx, dy = math.cos(angle), math.sin(angle)
    nx, ny = -dy, dx
    corners = [
        (cx - dx * half_length - nx * half_width, cy - dy * half_length - ny * half_width),
        (cx + dx * half_length - nx * half_width, cy + dy * half_length - ny * half_width),
        (cx + dx * half_length + nx * half_width, cy + dy * half_length + ny * half_width),
        (cx - dx * half_length + nx * half_width, cy - dy * half_length + ny * half_width),
    ]
    draw.polygon(corners, fill=255)

    # Light to deep blue across the band's width, upper edge to lower
    gradient = Image.new("RGB", (1, 256))
    for y in range(256):
        t = y / 255
        gradient.putpixel((0, y), tuple(round(a + (b - a) * t) for a, b in zip(RIBBON_TOP, RIBBON_BOTTOM)))
    length = int(half_length * 2)
    # A little wider than the band, so its rotated edges carry no dark fringe
    strip = gradient.resize((length, int(width) + 6), Image.BILINEAR)
    colour = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    rotated = strip.rotate(-45, expand=True, resample=Image.BICUBIC)
    colour.paste(rotated, (int(cx - rotated.width / 2), int(cy - rotated.height / 2)))
    colour.putalpha(band)

    # DEV along the band, reading down and to the right
    font = load_font(font_path, int(width * 0.62))
    text = Image.new("L", (int(width * 4), int(width)), 0)
    text_draw = ImageDraw.Draw(text)
    l, t, r, b = text_draw.textbbox((0, 0), "DEV", font=font)
    # Letter-spaced a little, as a label is
    spacing = width * 0.08
    widths = [text_draw.textlength(ch, font=font) for ch in "DEV"]
    total = sum(widths) + spacing * 2
    x = (text.width - total) / 2
    y = (text.height - (b - t)) / 2 - t
    for ch, w in zip("DEV", widths):
        text_draw.text((x, y), ch, font=font, fill=255)
        x += w + spacing
    text = text.rotate(-45, expand=True, resample=Image.BICUBIC)
    lettering = Image.new("L", (size, size), 0)
    lettering.paste(text, (int(cx - text.width / 2), int(cy - text.height / 2)))
    colour = Image.composite(Image.new("RGBA", (size, size), TEXT + (255,)), colour, lettering)
    return colour, band


def draw_dev_icon(icon, font_path):
    size = icon.width
    mask = squircle_mask(icon)
    box = mask.point(lambda v: 255 if v > 200 else 0).getbbox()
    colour, band = ribbon(size, box, font_path)

    # A soft shadow under the ribbon, so it sits on the icon rather than in it
    shadow = band.filter(ImageFilter.GaussianBlur(size * 0.012)).point(lambda v: v * 0.35)
    shadow = ImageChops.offset(shadow, 0, int(size * 0.006))
    shadow = ImageChops.multiply(shadow, mask)
    shaded = Image.composite(Image.new("RGBA", icon.size, (0, 0, 0, 255)), icon, shadow)
    shaded.putalpha(icon.getchannel("A"))

    # The ribbon only where the rounded square is
    ribbon_alpha = ImageChops.multiply(colour.getchannel("A"), mask)
    colour.putalpha(ribbon_alpha)
    result = Image.alpha_composite(shaded, colour)
    result.putalpha(icon.getchannel("A"))
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--font", help="a bold font file for the word DEV")
    args = parser.parse_args()
    font_path = args.font or next((f for f in FONT_CANDIDATES if Path(f).exists()), None)
    if font_path is None:
        parser.error("no bold font found; pass one with --font")

    contents = json.loads((SOURCE / "Contents.json").read_text())
    images = [entry for entry in contents["images"] if "filename" in entry]
    largest = max(images, key=lambda e: Image.open(SOURCE / e["filename"]).width)
    master = draw_dev_icon(Image.open(SOURCE / largest["filename"]).convert("RGBA"), font_path)

    TARGET.mkdir(exist_ok=True)
    for entry in images:
        width = Image.open(SOURCE / entry["filename"]).width
        image = master if width == master.width else master.resize((width, width), Image.LANCZOS)
        image.save(TARGET / entry["filename"], optimize=True)
        print(f"wrote {entry['filename']} ({width} px)")
    shutil.copyfile(SOURCE / "Contents.json", TARGET / "Contents.json")


if __name__ == "__main__":
    main()
