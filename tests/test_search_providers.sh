#!/usr/bin/env bash
# The two pieces of Search that are logic rather than wiring: the recently-used.xbel
# parser in FileSearch.qml and the settings page argument derived from a component
# filename in SettingsPages.qml.
#
# Both are plain JavaScript lifted out of the real source and run as-is, so a change
# to the QML is a change to what this runs. The parser is fed a fixture, never the
# user's own recently-used.xbel.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$REPO_ROOT/dots/.config/quickshell/koompi"

command -v node > /dev/null || { printf 'node is not installed; skipping\n'; exit 0; }

FILE_SEARCH="$QS/services/FileSearch.qml" \
SETTINGS_PAGES="$QS/services/SettingsPages.qml" \
SETTINGS_WINDOW="$QS/settings.qml" \
node - <<'EOF'
const fs = require("fs");

// Lift `function name(...) { ... }` out of a QML file by matching braces, so the
// test always exercises the source rather than a copy of it.
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

let failures = 0;
function check(what, ok) {
    if (!ok) { console.error(`  xx ${what}`); failures++; }
}

//////////////////// recently-used.xbel ////////////////////
const parseXbel = lift(process.env.FILE_SEARCH, "parseXbel");

const fixture = `<?xml version="1.0" encoding="UTF-8"?>
<xbel version="1.0">
  <bookmark href="file:///home/u/Documents/older.pdf" added="2026-07-01T00:00:00Z" modified="2026-07-01T00:00:00Z" visited="2026-07-01T00:00:00Z"/>
  <bookmark href="file:///home/u/a%20space%20%26%20sign.txt" added="2026-07-30T09:00:00Z" modified="2026-07-30T09:00:00Z"/>
  <bookmark modified="2026-07-29T00:00:00Z" href="file:///home/u/attrs-out-of-order.md"/>
  <bookmark href="https://example.com/not-a-file" modified="2026-07-31T00:00:00Z"/>
  <bookmark href="file:///home/u/no-modified.txt"/>
</xbel>`;

const parsed = parseXbel(fixture);
check("non-file:// bookmarks are dropped", !parsed.some(e => e.path.includes("example.com")));
check("every file:// bookmark is kept", parsed.length === 4);
check("percent-escapes are decoded", parsed.some(e => e.name === "a space & sign.txt"));
check("href is found regardless of attribute order", parsed.some(e => e.name === "attrs-out-of-order.md"));
check("newest first", parsed[0].name === "a space & sign.txt");
check("an entry without modified sorts last rather than vanishing", parsed[parsed.length - 1].name === "no-modified.txt");
check("name is the basename, path is absolute", parsed[0].path === "/home/u/a space & sign.txt");
check("an empty file yields nothing instead of throwing", parseXbel("").length === 0);

//////////////////// settings page argument ////////////////////
const pageArg = lift(process.env.SETTINGS_PAGES, "pageArg");
const pagesSrc = fs.readFileSync(process.env.SETTINGS_PAGES, "utf8");
const components = [...pagesSrc.matchAll(/component:\s*"([^"]+)"/g)].map(m => m[1]);

check("the page list survived the move to the singleton", components.length > 10);
check("settings.qml reads the shared list", /property var pages:\s*SettingsPages\.list/.test(fs.readFileSync(process.env.SETTINGS_WINDOW, "utf8")));

// Search hands `koompi-settings` this argument; settings.qml then resolves it
// with `component.toLowerCase().includes(requested)`. An argument that matches
// two components would silently open the wrong page.
for (const component of components) {
    const arg = pageArg({ component });
    const matches = components.filter(c => c.toLowerCase().includes(arg));
    check(`"${arg}" resolves to exactly one page (got ${matches.length})`, matches.length === 1);
    check(`"${arg}" resolves back to ${component}`, matches[0] === component);
    check(`"${arg}" is non-empty and lowercase`, arg.length > 0 && arg === arg.toLowerCase());
}

if (failures > 0) { console.error(`${failures} check(s) failed`); process.exit(1); }
console.log(`search provider test passed (${parsed.length} bookmarks, ${components.length} settings pages)`);
EOF
