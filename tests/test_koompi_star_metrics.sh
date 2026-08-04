#!/usr/bin/env bash
# The Super keycap draws U+100000 from KoompiStar.ttf, and two of that font's
# metrics do not match the monospace face it sits beside:
#
#   advance   1.00 em against JetBrains Mono's 0.60 -> a wider cap
#   line box  1.00 em against 1.32                  -> a shorter cap
#   ink       y -14..726 against a line box centred at y 300 -> the star draws high
#
# KeyboardKey.qml sizes the cap off a hidden monospace "W" for the first two and
# carries `koompiGlyphRise` for the third. That constant is derived from the ttf
# and nothing links them, so rebuilding the font with a different TARGET_HEIGHT or
# BOTTOM silently un-centres the star. This recomputes it from the shipped file.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TTF="$ROOT/sdata/dist-arch/ttf-koompi-star/files/KoompiStar.ttf"
QML="$ROOT/dots/.config/quickshell/koompi/modules/common/widgets/KeyboardKey.qml"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$TTF" ]] || fail "missing $TTF"
[[ -f "$QML" ]] || fail "missing $QML"

declared="$(grep -oE 'property real koompiGlyphRise: [0-9.]+' "$QML" | grep -oE '[0-9.]+$')"
[[ -n "$declared" ]] || fail "koompiGlyphRise is gone from KeyboardKey.qml; the star will draw high again"

measured="$(python3 - "$TTF" <<'PY'
import struct, sys
d = open(sys.argv[1], 'rb').read()
tabs = {}
for i in range(struct.unpack('>H', d[4:6])[0]):
    o = 12 + 16 * i
    tabs[d[o:o+4].decode()] = struct.unpack('>II', d[o+8:o+16])
for t in ('head', 'hhea', 'loca', 'glyf'):
    if t not in tabs:
        sys.exit(f"no {t} table")
ho = tabs['head'][0]
upm = struct.unpack('>H', d[ho+18:ho+20])[0]
long_loca = struct.unpack('>h', d[ho+50:ho+52])[0]
hh = tabs['hhea'][0]
asc, desc = struct.unpack('>hh', d[hh+4:hh+8])
lo, ll = tabs['loca']
loca = ([x * 2 for x in struct.unpack('>%dH' % (ll // 2), d[lo:lo+ll])] if long_loca == 0
        else list(struct.unpack('>%dI' % (ll // 4), d[lo:lo+ll])))
# glyph order is .notdef, space, koompistar
gi = 2
if gi + 1 >= len(loca) or loca[gi] == loca[gi+1]:
    sys.exit("glyph 2 (koompistar) is empty")
s = tabs['glyf'][0] + loca[gi]
_, _, ymin, _, ymax = struct.unpack('>hhhhh', d[s:s+10])
# how far the ink centre sits above the line-box centre, in em: the distance
# centerIn leaves behind and koompiGlyphRise pushes back down
print(f"{((ymin + ymax) / 2 - (asc + desc) / 2) / upm:.4f}")
PY
)" || fail "could not read metrics out of $TTF"

# Negative would mean the ink sits below the line-box centre and the offset would
# have to lift, not drop, which the QML's one-directional name no longer describes.
awk -v m="$measured" 'BEGIN { exit (m > 0) ? 0 : 1 }' \
    || fail "the ttf now centres its ink at or below the line-box centre (measured $measured); koompiGlyphRise no longer describes the fix"

delta="$(awk -v m="$measured" -v q="$declared" 'BEGIN { printf "%.4f", m - q }')"
awk -v d="$delta" 'BEGIN { exit (d < 0.0005 && d > -0.0005) ? 0 : 1 }' \
    || fail "koompiGlyphRise is $declared but KoompiStar.ttf measures $measured; the star draws $delta em off centre"

# The rise is a fraction of the em, so it has to be taken against whatever size the
# glyph is actually rendered at. Scaling the glyph and leaving the rise on the base
# pixelSize re-opens the gap by rise * (scale - 1), silently and only for the star.
size_expr="$(grep -oE 'font\.pixelSize: root\.koompiGlyph \? [A-Za-z.]+' "$QML" | awk '{print $NF}')"
rise_expr="$(grep -oE 'verticalCenterOffset: root\.koompiGlyph \? [A-Za-z.]+' "$QML" | awk '{print $NF}')"
[[ -n "$size_expr" && -n "$rise_expr" ]] \
    || fail "could not find the star's font.pixelSize and verticalCenterOffset branches in KeyboardKey.qml"
[[ "$size_expr" == "$rise_expr" ]] \
    || fail "the star renders at $size_expr but its rise is taken against $rise_expr; the two must be the same size or the star drifts off centre as it is scaled"

printf 'ok: koompiGlyphRise %s matches KoompiStar.ttf (%s em), rise taken against %s\n' \
    "$declared" "$measured" "$size_expr"
