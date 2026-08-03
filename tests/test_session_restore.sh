#!/usr/bin/env bash
# The one path in SessionRestore.qml that has to be right before anyone can log in:
# whether a saved session is safe to replay. It runs at login, so a state file
# truncated by a crash or written by another version must be discarded, never half
# applied.
#
# Functions are lifted out of the real QML and run as-is. Every input is a fixture.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$REPO_ROOT/dots/.config/quickshell/koompi"

command -v node > /dev/null || { printf 'node is not installed; skipping\n'; exit 0; }

SESSION_RESTORE="$QS/services/SessionRestore.qml" \
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

const SRC = process.env.SESSION_RESTORE;

// The lifted functions call each other through `root`, which is the QML
// singleton at runtime and this object here.
const root = {
    isWorkspaceId: lift(SRC, "isWorkspaceId"),
    parseState: lift(SRC, "parseState"),
    snapshot: lift(SRC, "snapshot"),
};

// `snapshot` reads the live client list; stand in for it.
let HyprlandData = { windowList: [], activeWorkspace: null };
globalThis.HyprlandData = HyprlandData;

let failures = 0;
function check(what, ok) {
    if (!ok) { console.error(`  xx ${what}`); failures++; }
}

const good = JSON.stringify({
    version: 1,
    workspace: 3,
    windows: [{ class: "kitty", workspace: 1 }, { class: "org.kde.dolphin", workspace: 3 }],
});

const rejected = {
    "empty file": "",
    "whitespace only": "   \n",
    "not json at all": "\u0000\u0000\u0000garbage",
    "truncated mid-object": good.slice(0, good.length - 12),
    "truncated mid-string": good.slice(0, 40),
    "json null": "null",
    "json array": "[]",
    "json string": '"hello"',
    "json number": "7",
    "missing version": JSON.stringify({ workspace: 1, windows: [] }),
    "future version": JSON.stringify({ version: 2, workspace: 1, windows: [] }),
    "version as string": JSON.stringify({ version: "1", workspace: 1, windows: [] }),
    "windows missing": JSON.stringify({ version: 1, workspace: 1 }),
    "windows not a list": JSON.stringify({ version: 1, workspace: 1, windows: {} }),
    "workspace missing": JSON.stringify({ version: 1, windows: [] }),
    "workspace zero": JSON.stringify({ version: 1, workspace: 0, windows: [] }),
    "workspace negative": JSON.stringify({ version: 1, workspace: -99, windows: [] }),
    "workspace above range": JSON.stringify({ version: 1, workspace: 101, windows: [] }),
    "workspace fractional": JSON.stringify({ version: 1, workspace: 1.5, windows: [] }),
    "workspace as string": JSON.stringify({ version: 1, workspace: "3", windows: [] }),
    "window is null": JSON.stringify({ version: 1, workspace: 1, windows: [null] }),
    "window is a string": JSON.stringify({ version: 1, workspace: 1, windows: ["kitty"] }),
    "window class missing": JSON.stringify({ version: 1, workspace: 1, windows: [{ workspace: 1 }] }),
    "window class empty": JSON.stringify({ version: 1, workspace: 1, windows: [{ class: "", workspace: 1 }] }),
    "window workspace missing": JSON.stringify({ version: 1, workspace: 1, windows: [{ class: "kitty" }] }),
    "window workspace special": JSON.stringify({ version: 1, workspace: 1, windows: [{ class: "kitty", workspace: -98 }] }),
    // A file that is partly wrong is a file of unknown provenance: the good
    // entries beside a bad one are not trustworthy either.
    "one bad entry among good ones": JSON.stringify({
        version: 1,
        workspace: 1,
        windows: [{ class: "kitty", workspace: 1 }, { class: "dolphin", workspace: 999 }],
    }),
};

for (const [name, text] of Object.entries(rejected)) {
    let result;
    try {
        result = root.parseState(text);
    } catch (e) {
        check(`${name} threw instead of being discarded: ${e}`, false);
        continue;
    }
    check(`${name} was replayed instead of discarded`, result === null);
}

const parsed = root.parseState(good);
check("a well-formed session was discarded", parsed !== null);
check("the focused workspace was lost", parsed?.workspace === 3);
check("the window list was lost", parsed?.windows?.length === 2);
check("a window class was lost", parsed?.windows?.[0]?.class === "kitty");
check("a window workspace was lost", parsed?.windows?.[1]?.workspace === 3);

const empty = root.parseState(JSON.stringify({ version: 1, workspace: 1, windows: [] }));
check("a session with no windows was discarded", empty !== null && empty.windows.length === 0);

const edges = root.parseState(JSON.stringify({
    version: 1, workspace: 100, windows: [{ class: "a", workspace: 1 }, { class: "b", workspace: 100 }],
}));
check("workspaces 1 and 100 were rejected", edges !== null);

HyprlandData.windowList = [
    { class: "kitty", workspace: { id: 2 } },
    { class: "org.kde.dolphin", workspace: { id: 5 } },
    // Never worth putting back: a special workspace, the lock screen's
    // temporary one, and a window with no class to look an entry up by.
    { class: "discord", workspace: { id: -98 } },
    { class: "hyprlock", workspace: { id: 2147483646 } },
    { class: "", workspace: { id: 1 } },
];
HyprlandData.activeWorkspace = { id: 5 };

const written = root.parseState(JSON.stringify(root.snapshot()));
check("a fresh snapshot failed its own validator", written !== null);
check("the snapshot lost the active workspace", written?.workspace === 5);
check("the snapshot kept a window it cannot restore", written?.windows?.length === 2);

HyprlandData.windowList = [];
HyprlandData.activeWorkspace = null;
const bare = root.parseState(JSON.stringify(root.snapshot()));
check("a snapshot with no active workspace failed validation", bare !== null && bare.workspace === 1);

if (failures > 0) {
    console.error(`${failures} check(s) failed`);
    process.exit(1);
}
EOF
