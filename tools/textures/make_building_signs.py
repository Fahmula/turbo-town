#!/usr/bin/env python3
"""Shop fascia signs for facade.gdshader (realism branch).

Writes assets/textures/building/facade_signs.png: 16 rows of 1024 x 128 px,
RGB = the painted sign board (muted accent colour, inset border, lettering),
A = the lettering (the shader lights it at night). The first 12 rows are the
shop types of the interior atlas, in the same order as SHOPS in
tools/blender/make_building_interiors.py; rows 12-15 are extra trades.
Only generic trade words, no names or brands.

Fonts: Fira Sans (SIL OFL 1.1) and Noto Serif (SIL OFL 1.1) from the system
font folders; the glyphs end up in the PNG, no font file is shipped.
Run from the project root: python3 tools/textures/make_building_signs.py
"""
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT = os.path.join(ROOT, "assets", "textures", "building", "facade_signs.png")
W, H = 1024, 128

FIRA = "/usr/share/fonts/TTF/FiraSans-SemiBold.ttf"
FIRA_COND = "/usr/share/fonts/TTF/FiraSansCondensed-SemiBold.ttf"
NOTO_SERIF = "/usr/share/fonts/noto/NotoSerif-Bold.ttf"

OXBLOOD = (0x8C, 0x33, 0x2B)
NAVY = (0x2E, 0x4D, 0x73)
GREEN = (0x38, 0x61, 0x4A)
OCHRE = (0xB8, 0x85, 0x33)
CHARCOAL = (0x47, 0x47, 0x4D)
CREAM = (0xF2, 0xEB, 0xD8)
DARK = (0x2A, 0x24, 0x20)

# (word, board colour, letter colour, font, tracking px)
SIGNS = [
    ("CAFE", GREEN, CREAM, FIRA, 26),
    ("COFFEE", OXBLOOD, CREAM, NOTO_SERIF, 20),
    ("BOUTIQUE", CHARCOAL, CREAM, NOTO_SERIF, 18),
    ("FASHION", NAVY, CREAM, FIRA, 22),
    ("GROCERY", GREEN, CREAM, FIRA_COND, 16),
    ("RESTAURANT", OXBLOOD, CREAM, NOTO_SERIF, 10),
    ("BISTRO", CHARCOAL, CREAM, NOTO_SERIF, 24),
    ("BOOKS", NAVY, CREAM, NOTO_SERIF, 28),
    ("FLOWERS", GREEN, CREAM, FIRA, 20),
    ("HARDWARE", OCHRE, DARK, FIRA_COND, 16),
    ("ELECTRONICS", CHARCOAL, CREAM, FIRA_COND, 12),
    ("MARKET", OXBLOOD, CREAM, FIRA, 22),
    ("BAKERY", OCHRE, DARK, NOTO_SERIF, 20),
    ("DELI", NAVY, CREAM, FIRA, 40),
    ("PHARMACY", GREEN, CREAM, FIRA, 18),
    ("BARBER", CHARCOAL, CREAM, FIRA, 26),
]


def draw_row(word, board, ink, font_path, tracking):
    base = Image.new("RGB", (W, H), board)
    mask = Image.new("L", (W, H), 0)
    d = ImageDraw.Draw(base)
    # Inset border, slightly lighter than the board.
    light = tuple(min(255, int(c * 1.35 + 18)) for c in board)
    d.rectangle([10, 10, W - 11, H - 11], outline=light, width=3)
    # Fit the lettering to about 78% of the width, up to 64% of the height.
    size = 80
    for size in range(88, 20, -2):
        font = ImageFont.truetype(font_path, size)
        widths = [font.getlength(ch) for ch in word]
        total = sum(widths) + tracking * (len(word) - 1)
        bbox = font.getbbox("H")
        if total <= W * 0.78 and (bbox[3] - bbox[1]) <= H * 0.64:
            break
    x = (W - total) / 2
    cap = font.getbbox("H")
    y = (H - (cap[3] - cap[1])) / 2 - cap[1]
    md = ImageDraw.Draw(mask)
    for ch, w in zip(word, widths):
        md.text((x, y), ch, font=font, fill=255)
        d.text((x, y), ch, font=font, fill=ink)
        x += w + tracking
    base.putalpha(mask)
    return base


def main():
    atlas = Image.new("RGBA", (W, H * len(SIGNS)))
    for i, s in enumerate(SIGNS):
        atlas.paste(draw_row(*s), (0, i * H))
    atlas.save(OUT, optimize=True)
    print("wrote", OUT, atlas.size)


if __name__ == "__main__":
    main()
