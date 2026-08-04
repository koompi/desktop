#!/usr/bin/env python3
"""Regenerate files/KoompiStar.ttf from the repo's koompi-symbolic.svg.

Run when the brand mark changes. Needs fonttools; the built ttf is committed so
neither the PKGBUILD nor a clean-chroot build depends on it.

    python3 build-font.py
"""

import re
import sys
from pathlib import Path

from fontTools.fontBuilder import FontBuilder
from fontTools.pens.cu2quPen import Cu2QuPen
from fontTools.pens.recordingPen import RecordingPen
from fontTools.pens.transformPen import TransformPen
from fontTools.pens.ttGlyphPen import TTGlyphPen
from fontTools.svgLib.path import parse_path

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[2]
SVG = REPO / "dots/.config/quickshell/koompi/assets/icons/koompi-symbolic.svg"
OUT = HERE / "files/KoompiStar.ttf"

UPM = 1000
# Plane 16 private use. The BMP PUA is not free: ttf-material-symbols-variable
# claims most of it (E8F0-EA5F included) and Nerd Fonts owns the rest plus
# Plane 15. Both are siblings in koompi-fonts-themes, so a BMP codepoint would
# be shadowed by whichever face fontconfig sorted first.
CODEPOINT = 0x100000
GLYPH = "koompistar"

# Everything below matches JetBrains Mono NF, the face the star sits beside, so
# the glyph behaves like one of its characters instead of needing the caller to
# correct it. Measured from its own Windows mark, U+E8E5, which is what the Super
# keycap drew before the star:
#
#   advance 600, the same cell as a letter, so a cap sized off the glyph is the
#           width of a cap sized off "W"
#   hhea 1020/-300, the same line box, so the two stack identically
#   ink 800x800 centred on the line-box centre at y 360, exactly, so centring the
#           text item centres the mark and no offset is left over
#
# The ink is deliberately taller than the 730 cap height and wider than the 600
# cell. That overshoot is what makes a mark read at the same weight as the
# letters around it; bleeding past the advance is normal for an icon glyph.
ASCENT = 1020
DESCENT = -300
CAP_HEIGHT = 730
ADVANCE = 600
# Same 800 as the Windows mark. The ink overhangs the 600 cell by 100 a side,
# which is what an icon glyph does and what a terminal still renders cleanly;
# going further to fill the Super keycap would collide with the characters
# beside it in a prompt. The keycap earns its size from tighter padding instead.
TARGET_SIZE = 800
# Centre the ink on the line box rather than pinning it to the baseline.
INK_CENTRE = (ASCENT + DESCENT) / 2
BOTTOM = INK_CENTRE - TARGET_SIZE / 2

# potrace writes y-up path data under a negative-y group transform, which the
# y-down SVG space then cancels. Reading the raw coordinates as y-up is correct;
# no flip belongs here.


def svg_paths(svg_text):
    paths = re.findall(r'<path[^>]*\sd="([^"]+)"', svg_text)
    if not paths:
        sys.exit(f"no <path d=...> found in {SVG}")
    return paths


def record(paths):
    rec = RecordingPen()
    for d in paths:
        parse_path(d, rec)
    return rec


def bounds(rec):
    xs, ys = [], []
    for _op, args in rec.value:
        for pt in args:
            if isinstance(pt, tuple):
                xs.append(pt[0])
                ys.append(pt[1])
    return min(xs), min(ys), max(xs), max(ys)


def main():
    if not SVG.exists():
        sys.exit(f"missing artwork: {SVG}")
    rec = record(svg_paths(SVG.read_text(encoding="utf-8")))
    x0, y0, x1, y1 = bounds(rec)
    # Each axis scaled to the same target rather than one scale off the height.
    # potrace traced the mark a hair wider than tall, and carrying that through
    # lands the vertical tips on different pixel fractions than the horizontal
    # ones, which is what makes the top and bottom edges read soft.
    # These read the raw <path d=...>, so any <g transform> on the SVG is not
    # seen here; the artwork's own viewBox has no bearing on the glyph.
    sx = TARGET_SIZE / (x1 - x0)
    sy = TARGET_SIZE / (y1 - y0)
    dx = (ADVANCE - TARGET_SIZE) / 2 - x0 * sx
    dy = BOTTOM - y0 * sy

    ttpen = TTGlyphPen(None)
    rec.replay(TransformPen(Cu2QuPen(ttpen, 1.0), (sx, 0, 0, sy, dx, dy)))
    star = ttpen.glyph()

    empty = TTGlyphPen(None).glyph()
    fb = FontBuilder(UPM, isTTF=True)
    order = [".notdef", "space", GLYPH]
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({0x20: "space", CODEPOINT: GLYPH})
    fb.setupGlyf({".notdef": empty, "space": empty, GLYPH: star})
    # lsb has to be the glyph's own xMin, not 0: the ink is wider than the cell
    # and starts left of it, and a renderer that positions off hmtx rather than
    # glyf would shift the mark by the difference.
    star_lsb = round(dx + x0 * sx)
    fb.setupHorizontalMetrics({g: (ADVANCE, star_lsb if g == GLYPH else 0)
                               for g in order})
    fb.setupHorizontalHeader(ascent=ASCENT, descent=DESCENT)
    fb.setupNameTable({
        "familyName": "KOOMPI Star",
        "styleName": "Regular",
        "uniqueFontIdentifier": "KOOMPI Star Regular; 1.000",
        "fullName": "KOOMPI Star Regular",
        "version": "Version 1.000",
        "psName": "KOOMPIStar-Regular",
        "manufacturer": "KOOMPI",
        "designer": "KOOMPI",
        "description": "The KOOMPI star as a single glyph at U+100000, for the "
                       "Super key and anywhere the mark must be a character.",
    })
    fb.setupOS2(sTypoAscender=ASCENT, sTypoDescender=DESCENT, sTypoLineGap=0,
                usWinAscent=ASCENT, usWinDescent=-DESCENT,
                sCapHeight=CAP_HEIGHT, achVendID="KMPI")
    fb.setupPost(isFixedPitch=1)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fb.save(OUT)

    print(f"wrote {OUT.relative_to(REPO)}")
    print(f"  source bbox {x1 - x0:.0f}x{y1 - y0:.0f} -> {TARGET_SIZE}x{TARGET_SIZE} at {UPM} upm")
    print(f"  U+{CODEPOINT:04X} advance {ADVANCE}, lsb {star_lsb}, ink centred on y {INK_CENTRE:.0f}")


if __name__ == "__main__":
    main()
