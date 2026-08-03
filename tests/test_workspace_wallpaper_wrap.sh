#!/usr/bin/env bash
# Config declares ten workspace wallpaper slots, so the shell wraps higher workspaces
# onto them by decade. Two things must agree: the modulus in the QML and the ten
# slots the helper script seeds. If they drift, workspaces silently share the wrong
# picture or fall back to the global one.
#
# The resolver is lifted out of the real QML and run as-is; Config is a fixture.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WALLPAPERS="$REPO_ROOT/dots/.config/quickshell/koompi/services/Wallpapers.qml"
HELPER="$REPO_ROOT/dots/.config/hypr/custom/scripts/koompi-wallpaper.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# The old clamp is the regression: anything past 10 got an empty key.
grep -q 'workspaceId <= 10' "$WALLPAPERS" \
    && fail "rawForWorkspace clamps at 10 again instead of wrapping"

grep -q 'reduce range(1; 11)' "$HELPER" || fail "helper no longer seeds ten slots"
grep -q 'for i in {1\.\.10}' "$HELPER" || fail "helper seed loop no longer covers ten slots"
grep -q '\^(\[1-9\]|10)\$' "$HELPER" || fail "helper no longer validates slots as 1-10"

command -v node > /dev/null || { printf 'node is not installed; skipping\n'; exit 0; }

WALLPAPERS="$WALLPAPERS" node - <<'EOF'
const fs = require("fs");

// Lift `function name(...): type { ... }` out of a QML file by matching braces,
// dropping the QML type annotations JavaScript cannot parse.
function lift(path, name, args) {
    const src = fs.readFileSync(path, "utf8");
    const start = src.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} is gone from ${path}`);
    let i = src.indexOf("{", start), depth = 0, end = -1;
    for (let j = i; j < src.length; j++) {
        if (src[j] === "{") depth++;
        else if (src[j] === "}" && --depth === 0) { end = j + 1; break; }
    }
    if (end < 0) throw new Error(`unbalanced braces in ${name}`);
    return eval(`(function (${args}) ${src.slice(i, end)})`);
}

const rawForWorkspace = lift(process.env.WALLPAPERS, "rawForWorkspace", "workspaceId");

const FALLBACK = "/usr/share/backgrounds/koompi/global.jpg";
const slots = {};
for (let i = 1; i <= 10; i++) slots[`ws${i}`] = { mode: "static", path: `/pics/${i}.jpg` };

globalThis.Config = { options: { background: {
    wallpaperPath: FALLBACK,
    workspaceWallpapers: { enabled: true, defaultMode: "inherit", workspaces: slots },
}}};

let failures = 0;
function same(what, got, want) {
    if (got !== want) { console.error(`  xx ${what}: got ${got}, wanted ${want}`); failures++; }
}
function check(what, ok) {
    if (!ok) { console.error(`  xx ${what}`); failures++; }
}

for (let i = 1; i <= 10; i++) same(`workspace ${i}`, rawForWorkspace(i), `/pics/${i}.jpg`);

same("workspace 11", rawForWorkspace(11), "/pics/1.jpg");
same("workspace 20", rawForWorkspace(20), "/pics/10.jpg");
same("workspace 21", rawForWorkspace(21), "/pics/1.jpg");
same("workspace 23", rawForWorkspace(23), "/pics/3.jpg");
same("workspace 100", rawForWorkspace(100), "/pics/10.jpg");

// The bug: every workspace past ten showing the same thing.
check("workspaces 11 and 12 still share a wallpaper",
    rawForWorkspace(11) !== rawForWorkspace(12));

// Hyprland's special workspaces are negative, and % would hand back "ws0" or
// "ws-3" and quietly miss.
same("workspace 0", rawForWorkspace(0), FALLBACK);
same("workspace -1", rawForWorkspace(-1), FALLBACK);
same("workspace -99", rawForWorkspace(-99), FALLBACK);

Config.options.background.workspaceWallpapers.enabled = false;
same("workspace 13 with the feature off", rawForWorkspace(13), FALLBACK);
Config.options.background.workspaceWallpapers.enabled = true;

slots.ws3.mode = "inherit";
same("workspace 3 on inherit", rawForWorkspace(3), FALLBACK);
same("workspace 23 on inherit", rawForWorkspace(23), FALLBACK);
slots.ws3.mode = "static";

slots.ws4.path = "";
same("workspace 24 with an empty path", rawForWorkspace(24), FALLBACK);

if (failures > 0) {
    console.error(`${failures} check(s) failed`);
    process.exit(1);
}
EOF
