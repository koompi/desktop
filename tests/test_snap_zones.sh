#!/usr/bin/env bash
# The one piece of arithmetic in the snap preview: turning a pointer position
# into the rectangle a dropped window will occupy. It decides both what is drawn
# and where the window ends up, so the two can only agree if this is right.
#
# The function is lifted out of the real QML and run as-is, so this exercises the
# source rather than a copy. Nothing is dispatched and no compositor is touched:
# every input is a fixture.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$REPO_ROOT/dots/.config/quickshell/koompi"

command -v node > /dev/null || { printf 'node is not installed; skipping\n'; exit 0; }

SNAP_PREVIEW="$QS/modules/koompi/snapPreview/SnapPreview.qml" \
node - <<'EOF'
const fs = require("fs");

// Lift `function name(...) { ... }` out of a QML file by matching braces.
function lift(path, name) {
    const src = fs.readFileSync(path, "utf8");
    const start = src.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} is gone from ${path}`);
    let i = src.indexOf("{", start), depth = 0, end = -1;
    for (let j = i; j < src.length; j++) {
        if (src[j] === "{") depth++;
        else if (src[j] === "}" && --depth === 0) { end = j + 1; break; }
    }
    if (end < 0) throw new Error(`unbalanced braces in ${name}`);
    return eval(`(${src.slice(start, end).replace(`function ${name}`, "function")})`);
}

// The lifted function reads its two constants off `root`, which is the QML
// component at runtime and this object here. The values are the shipped ones:
// `edgeThreshold` from SnapPreview.qml, `gap` from Hyprland's `gaps_out`.
const root = { edgeThreshold: 24, gap: 5 };
root.dropRectFor = lift(process.env.SNAP_PREVIEW, "dropRectFor");
root.pointInWindow = lift(process.env.SNAP_PREVIEW, "pointInWindow");

// A 1920x1200 output with a 40px bar reserved at the top, which is this
// project's default.
const W = 1920, H = 1200, RESERVED = [0, 40, 0, 0];
const at = (x, y) => root.dropRectFor(W, H, RESERVED, x, y);

// Usable area after the bar and the gap Hyprland leaves around a tile.
const UX = 5, UY = 45, UW = 1910, UH = 1150;
const HALF_W = (UW - 5) / 2, HALF_H = (UH - 5) / 2;

let failures = 0;
function check(what, ok) {
    if (!ok) { console.error(`  xx ${what}`); failures++; }
}
function same(what, got, want) {
    const ok = got !== null && want !== null
        && Math.abs(got.x - want.x) < 0.001 && Math.abs(got.y - want.y) < 0.001
        && Math.abs(got.width - want.width) < 0.001 && Math.abs(got.height - want.height) < 0.001;
    check(`${what}: got ${JSON.stringify(got)}, wanted ${JSON.stringify(want)}`, ok);
}

// --- no zone ------------------------------------------------------------
check("the middle of the screen snapped", at(960, 600) === null);
check("just inside the left edge snapped", at(25, 600) === null);
check("just inside the right edge snapped", at(W - 26, 600) === null);
check("the bottom edge snapped, over the dock", at(960, H - 1) === null);
check("the bottom-left corner without a side snapped", at(960, H - 1) === null);

// --- halves -------------------------------------------------------------
same("left edge", at(0, 600), { x: UX, y: UY, width: HALF_W, height: UH });
same("left edge at the threshold", at(24, 600), { x: UX, y: UY, width: HALF_W, height: UH });
same("right edge", at(W - 1, 600), { x: UX + UW - HALF_W, y: UY, width: HALF_W, height: UH });

// --- the top edge on its own maximises ----------------------------------
same("top edge", at(960, 0), { x: UX, y: UY, width: UW, height: UH });
// Under the bar, not above it: the reserved strip is not part of the target.
check("the maximised target overlapped the bar", at(960, 0).y >= RESERVED[1]);

// --- corners ------------------------------------------------------------
same("top-left corner", at(0, 0), { x: UX, y: UY, width: HALF_W, height: HALF_H });
same("top-right corner", at(W - 1, 0), { x: UX + UW - HALF_W, y: UY, width: HALF_W, height: HALF_H });
same("bottom-left corner", at(0, H - 1), { x: UX, y: UY + UH - HALF_H, width: HALF_W, height: HALF_H });
same("bottom-right corner", at(W - 1, H - 1), { x: UX + UW - HALF_W, y: UY + UH - HALF_H, width: HALF_W, height: HALF_H });

// --- the two halves tile the usable area --------------------------------
const left = at(0, 600), right = at(W - 1, 600);
check("the halves overlap", left.x + left.width <= right.x);
check("the halves leave a gap wider than Hyprland's", right.x - (left.x + left.width) === root.gap);
check("the halves do not fill the usable width", right.x + right.width === UX + UW);

// --- a bar on the bottom edge -------------------------------------------
const bottomBar = root.dropRectFor(W, H, [0, 0, 0, 40], 0, 600);
check("a bottom bar was not kept clear", bottomBar.y + bottomBar.height <= H - 40);

// --- the guard on acting at all -----------------------------------------
// A drag that did not start inside the window must not move it, or `Super`+drag
// on the desktop background flings whatever happened to be focused.
const win = { at: [100, 200], size: [800, 600] };
check("a drag from outside the window was accepted", !root.pointInWindow(50, 300, win));
check("a drag from below the window was accepted", !root.pointInWindow(300, 801, win));
check("a drag from inside the window was rejected", root.pointInWindow(300, 300, win));
check("the window's own top-left corner was rejected", root.pointInWindow(100, 200, win));
check("the pixel past the far edge was accepted", !root.pointInWindow(900, 300, win));
check("a missing window was accepted", !root.pointInWindow(300, 300, undefined));
check("a window with no geometry was accepted", !root.pointInWindow(300, 300, {}));

if (failures > 0) {
    console.error(`${failures} check(s) failed`);
    process.exit(1);
}
EOF
