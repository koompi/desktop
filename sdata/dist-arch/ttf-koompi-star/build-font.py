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
ADVANCE = UPM
# Spans the cap band with a hair of overshoot below the baseline, so the mark sits
# optically centred against uppercase rather than perched on it.
TARGET_HEIGHT = 740
BOTTOM = -14

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
    scale = TARGET_HEIGHT / (y1 - y0)
    width = (x1 - x0) * scale
    dx = (ADVANCE - width) / 2 - x0 * scale
    dy = BOTTOM - y0 * scale

    ttpen = TTGlyphPen(None)
    rec.replay(TransformPen(Cu2QuPen(ttpen, 1.0), (scale, 0, 0, scale, dx, dy)))
    star = ttpen.glyph()

    empty = TTGlyphPen(None).glyph()
    fb = FontBuilder(UPM, isTTF=True)
    order = [".notdef", "space", GLYPH]
    fb.setupGlyphOrder(order)
    fb.setupCharacterMap({0x20: "space", CODEPOINT: GLYPH})
    fb.setupGlyf({".notdef": empty, "space": empty, GLYPH: star})
    fb.setupHorizontalMetrics({g: (ADVANCE, 0) for g in order})
    fb.setupHorizontalHeader(ascent=800, descent=-200)
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
    fb.setupOS2(sTypoAscender=800, sTypoDescender=-200, sTypoLineGap=0,
                usWinAscent=800, usWinDescent=200,
                sCapHeight=TARGET_HEIGHT, achVendID="KMPI")
    fb.setupPost(isFixedPitch=1)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    fb.save(OUT)

    print(f"wrote {OUT.relative_to(REPO)}")
    print(f"  source bbox {x1 - x0:.0f}x{y1 - y0:.0f} -> {width:.0f}x{TARGET_HEIGHT} at {UPM} upm")
    print(f"  U+{CODEPOINT:04X} advance {ADVANCE}, lsb {dx + x0 * scale:.0f}")


if __name__ == "__main__":
    main()
