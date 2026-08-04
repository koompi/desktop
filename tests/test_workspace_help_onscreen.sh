#!/usr/bin/env bash
# The first-run workspace hint centres itself under the workspaces widget, which
# sits at the near end of its bar - so the centred offset goes negative and the
# hint hangs off the viewport. Layer-shell clips rather than nudging, so nothing
# downstream rescues it.
#
# Measured on 2026-08-04 before the fix: `hyprctl layers` reported the
# quickshell:workspaceHelp surface at `xywh: -180 36 380 200`, losing 180 of 380
# columns and with them the left half of every line of text.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/dots/.config/quickshell/koompi/modules/koompi/bar/WorkspaceHelp.qml"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$SRC" ]] || fail "missing $SRC"

grep -q 'function clampToScreen' "$SRC" \
    || fail "clampToScreen() is gone; the hint can hang off the viewport again"

# Both axes: `left` is the horizontal bar's failure and `top` is the vertical
# bar's, and they are the same mistake written twice.
margins="$(awk '/^        margins \{/,/^        \}/' "$SRC")"
[[ -n "$margins" ]] || fail "could not find the margins block in $SRC"

left_line="$(grep -A2 '^            left:' <<< "$margins")"
grep -q 'clampToScreen' <<< "$left_line" \
    || fail "the horizontal offset is unclamped; this is the -180 case that shipped"

top_line="$(grep -A2 '^            top:' <<< "$margins")"
grep -q 'clampToScreen' <<< "$top_line" \
    || fail "the vertical-bar offset is unclamped; same defect, other axis"

# The clamp is worthless if it is handed a constant instead of the real extents.
grep -q 'screen?\.width' <<< "$margins" \
    || fail "the horizontal clamp does not read the screen width"
grep -q 'screen?\.height' <<< "$margins" \
    || fail "the vertical clamp does not read the screen height"

# Guard the arithmetic itself: floor at 0, ceiling at screen minus window, and a
# window wider than the screen must not produce a negative ceiling.
python3 - <<'PY' || exit 1
def clamp(offset, window, screen):
    return min(max(0, offset), max(0, screen - window))

cases = [
    (-180, 380, 1920,    0, "the shipped defect: negative offset pinned to the edge"),
    ( 780, 380, 1920,  780, "a fitting offset is left alone"),
    (1800, 380, 1920, 1540, "an overhanging offset is pulled back to the far edge"),
    ( 100, 2000, 1920,   0, "a window wider than the screen still starts at 0"),
]
for offset, window, screen, want, why in cases:
    got = clamp(offset, window, screen)
    if got != want:
        raise SystemExit(f"clamp({offset},{window},{screen}) = {got}, want {want} - {why}")
PY

echo "ok"
