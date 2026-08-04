#!/usr/bin/env bash
# The Super keycap draws U+100000 from KoompiStar.ttf beside JetBrains Mono NF.
# The font used to carry its own metrics and KeyboardKey.qml corrected for them:
# a full-em advance against monospace's 0.6, a 1.0 em line box against 1.32, and
# ink centred 56/1000 em above the line-box centre, fixed with a rise constant, a
# 1.25 scale and a cap measured off a hidden "W".
#
# It now matches the face it sits beside, the way Nerd Fonts' own marks do, so
# none of those corrections exist. This guards that: if the font drifts back off
# the host's metrics the glyph silently mis-sizes and mis-centres again, and the
# fix belongs in build-font.py, not in the caller.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TTF="$ROOT/sdata/dist-arch/ttf-koompi-star/files/KoompiStar.ttf"
QML="$ROOT/dots/.config/quickshell/koompi/modules/common/widgets/KeyboardKey.qml"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$TTF" ]] || fail "missing $TTF"
[[ -f "$QML" ]] || fail "missing $QML"

# Targets are JetBrains Mono NF's, measured from its own Windows mark U+E8E5,
# which is what the Super keycap drew before the star.
WANT_ASCENT=1020
WANT_DESCENT=-300
WANT_ADVANCE=600

read -r upm asc desc adv xmin ymin xmax ymax < <(python3 - "$TTF" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
tabs = {}
for i in range(struct.unpack('>H', d[4:6])[0]):
    o = 12 + 16 * i
    tabs[d[o:o+4].decode('latin1')] = struct.unpack('>II', d[o+8:o+16])
for t in ('head', 'hhea', 'hmtx', 'loca', 'glyf'):
    if t not in tabs:
        sys.exit(f"no {t} table")
ho = tabs['head'][0]
upm = struct.unpack('>H', d[ho+18:ho+20])[0]
long_loca = struct.unpack('>h', d[ho+50:ho+52])[0]
hh = tabs['hhea'][0]
asc, desc = struct.unpack('>hh', d[hh+4:hh+8])
num_h = struct.unpack('>H', d[hh+34:hh+36])[0]
lo, ll = tabs['loca']
loca = ([x * 2 for x in struct.unpack('>%dH' % (ll // 2), d[lo:lo+ll])] if long_loca == 0
        else list(struct.unpack('>%dI' % (ll // 4), d[lo:lo+ll])))
# glyph order is .notdef, space, koompistar
gi = 2
if gi + 1 >= len(loca) or loca[gi] == loca[gi+1]:
    sys.exit("glyph 2 (koompistar) is empty")
# hmtx stores numberOfHMetrics longHorMetrics and every glyph past that reuses
# the last advance, which is how a font with one advance for all of them compiles.
hm = tabs['hmtx'][0]
idx = min(gi, num_h - 1)
adv = struct.unpack('>H', d[hm + 4 * idx:hm + 4 * idx + 2])[0]
s = tabs['glyf'][0] + loca[gi]
_, xmin, ymin, xmax, ymax = struct.unpack('>hhhhh', d[s:s+10])
print(upm, asc, desc, adv, xmin, ymin, xmax, ymax)
PY
) || fail "could not read metrics out of $TTF"

[[ "$upm" == 1000 ]] || fail "KoompiStar is $upm upm; the targets below are per-1000"
[[ "$asc" == "$WANT_ASCENT" && "$desc" == "$WANT_DESCENT" ]] \
    || fail "KoompiStar hhea is $asc/$desc, JetBrains Mono NF is $WANT_ASCENT/$WANT_DESCENT; a different line box makes the keycap a different height than its neighbours"
[[ "$adv" == "$WANT_ADVANCE" ]] \
    || fail "KoompiStar advance is $adv, JetBrains Mono NF's cell is $WANT_ADVANCE; the cap will not be the width of a letter's"

# The point of the rebuild: ink centred on the line box, so centring the text
# item centres the mark and nothing is left over for the caller to correct.
offset="$(awk -v ymin="$ymin" -v ymax="$ymax" -v a="$asc" -v de="$desc" -v u="$upm" \
    'BEGIN { printf "%.4f", ((ymin + ymax) / 2 - (a + de) / 2) / u }')"
awk -v o="$offset" 'BEGIN { exit (o < 0.001 && o > -0.001) ? 0 : 1 }' \
    || fail "KoompiStar's ink centre sits $offset em off the line-box centre; centring the glyph will leave it visibly high or low"

# Ink has to overshoot the 730 cap height or the mark reads smaller than the
# letters beside it, which is what the old 1.25 scale in the caller was for.
# Capped at the Windows mark's 800 in the other direction: the ink already
# overhangs the 600 cell, and growing it to fill the Super keycap would collide
# with the characters beside it in a prompt or in terminal output.
ink_h=$((ymax - ymin))
ink_w=$((xmax - xmin))
[[ "$ink_h" -ge 780 && "$ink_h" -le 820 ]] \
    || fail "KoompiStar's ink is ${ink_h}/1000 em tall; JetBrains Mono NF's own mark is 800 against a 730 cap, and straying from that either makes the star read light among letters or makes it overhang its cell far enough to collide inline"

# Square, so the vertical tips land on the same pixel fractions as the
# horizontal ones. potrace traced the mark a hair wider than tall and
# build-font.py scales each axis separately to undo it; 2 units of slack is the
# rounding in the quadratic conversion, not a licence to drift.
delta_wh=$(( ink_w > ink_h ? ink_w - ink_h : ink_h - ink_w ))
[[ "$delta_wh" -le 2 ]] \
    || fail "KoompiStar's ink is ${ink_w}x${ink_h}, off square by ${delta_wh}/1000 em; the top and bottom edges will soften while the left and right stay crisp"

# Centred on its cell too, or the mark sits off to one side of the keycap.
ink_cx=$(( (xmin + xmax) / 2 ))
cell_cx=$((WANT_ADVANCE / 2))
delta_cx=$(( ink_cx > cell_cx ? ink_cx - cell_cx : cell_cx - ink_cx ))
[[ "$delta_cx" -le 2 ]] \
    || fail "KoompiStar's ink centres at x $ink_cx against a cell centre of $cell_cx; the mark will sit off to one side"

# Ink is wider than the cell it sits in, which is normal for a mark, but then lsb
# has to be the glyph's own xMin or a renderer positioning off hmtx shifts it.
lsb="$(python3 - "$TTF" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
tabs = {}
for i in range(struct.unpack('>H', d[4:6])[0]):
    o = 12 + 16 * i
    tabs[d[o:o+4].decode('latin1')] = struct.unpack('>II', d[o+8:o+16])
hh = tabs['hhea'][0]
num_h = struct.unpack('>H', d[hh+34:hh+36])[0]
hm = tabs['hmtx'][0]
gi = 2
if gi < num_h:
    print(struct.unpack('>h', d[hm + 4 * gi + 2:hm + 4 * gi + 4])[0])
else:
    # past numberOfHMetrics the lsbs are a plain int16 array after the pairs
    off = hm + 4 * num_h + 2 * (gi - num_h)
    print(struct.unpack('>h', d[off:off+2])[0])
PY
)" || fail "could not read lsb out of $TTF"
[[ "$lsb" == "$xmin" ]] \
    || fail "KoompiStar's lsb is $lsb but its xMin is $xmin; the two must agree or the mark shifts horizontally"

# The corrections are gone because the font no longer needs them. Reintroducing
# one here means someone patched the symptom instead of build-font.py.
for gone in koompiGlyphRise koompiGlyphScale koompiPixelSize monoRef; do
    if grep -q "$gone" "$QML"; then
        fail "$gone is back in KeyboardKey.qml; the font carries the host's metrics now, so a correction here means the ttf drifted and build-font.py is the place to fix it"
    fi
done

# glyphNudgeX/Y are the only offsets allowed, and only as small constants: the
# ttf is held centred on both axes above, so anything past a pixel or two is not
# an optical nudge but a metric correction growing back, and it belongs in
# build-font.py.
for axis in X Y; do
    case "$axis" in
        X) anchor='horizontalCenterOffset' ;;
        Y) anchor='verticalCenterOffset' ;;
    esac
    grep -q "$anchor" "$QML" || continue
    nudge="$(grep -oE "property real glyphNudge$axis: -?[0-9.]+" "$QML" | grep -oE -- '-?[0-9.]+$')"
    [[ -n "$nudge" ]] \
        || fail "KeyboardKey.qml sets $anchor from something other than glyphNudge$axis; the ttf centres its own ink, so an offset derived from anything else double-corrects"
    awk -v n="$nudge" 'BEGIN { exit (n <= 2 && n >= -2) ? 0 : 1 }' \
        || fail "glyphNudge$axis is $nudge px; that is past an optical nudge and means the ttf drifted off centre, which build-font.py fixes"
done

# The Super cap asks for an 18px mark and gets there by running the text item at
# glyphSize / koompiInkPerEm. That divisor is the fraction of the em this ttf
# actually inks, so rebuilding the font at a different TARGET_SIZE without
# changing it silently resizes every keycap star.
declared_ink="$(grep -oE 'koompiInkPerEm: [0-9.]+' "$QML" | grep -oE '[0-9.]+$')"
[[ -n "$declared_ink" ]] \
    || fail "koompiInkPerEm is gone from KeyboardKey.qml; the keycap star's size is derived from it"
measured_ink="$(awk -v h="$ink_h" -v u="$upm" 'BEGIN { printf "%.3f", h / u }')"
awk -v a="$declared_ink" -v b="$measured_ink" 'BEGIN { d = a - b; exit (d < 0.005 && d > -0.005) ? 0 : 1 }' \
    || fail "KeyboardKey.qml derives the keycap star from koompiInkPerEm $declared_ink but KoompiStar inks $measured_ink of its em; the mark will not come out at the size the cap asks for"

printf 'ok: KoompiStar matches JetBrains Mono NF (hhea %s/%s, advance %s, ink %s em, %s off centre), caller carries no corrections\n' \
    "$asc" "$desc" "$adv" "$ink_h" "$offset"
