#!/usr/bin/env bash
# Per-turn tool subsetting. gemma4-e4b drops digits out of its own reply once the
# serialised tool array passes its measured ceiling, so no request may cross it — and
# no tool may become permanently unreachable as a result. Runs the real functions out
# of ToolRegistry.qml. No network.
#
# Set DUMP_DIR to write each turn's subset out as JSON for the corruption harness.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REGISTRY="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/ToolRegistry.qml"
REQUESTER="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/Requester.qml"

[[ -f "$REGISTRY" ]] || { echo "missing $REGISTRY" >&2; exit 1; }
command -v bun >/dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

fail=0

# The budget has to reach every turn, not only the one answering a tool result.
grep -q 'subsetForTurn(format, limit, root.lastUserText(messages))' "$REQUESTER" \
    || { echo "FAIL: Requester no longer subsets an ordinary turn" >&2; fail=1; }
grep -q 'if (answeringATool) return JSON.stringify(declared).length > limit ? \[\] : declared;' "$REQUESTER" \
    || { echo "FAIL: the turn answering a tool result no longer goes out bare" >&2; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/run.mjs" <<'EOF'
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";

const qml = readFileSync(process.argv[2], "utf8");

function liftBlock(header, open, close) {
    const start = qml.indexOf(header);
    if (start < 0) throw new Error(`${header} not found in ToolRegistry.qml`);
    let depth = 0;
    for (let j = qml.indexOf(open, start); j < qml.length; j++) {
        if (qml[j] === open) depth++;
        else if (qml[j] === close && --depth === 0) return qml.slice(qml.indexOf(open, start), j + 1);
    }
    throw new Error(`unbalanced ${open} in ${header}`);
}

function liftFn(name) {
    const start = qml.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} not found in ToolRegistry.qml`);
    let depth = 0;
    for (let j = qml.indexOf("{", start); j < qml.length; j++) {
        if (qml[j] === "{") depth++;
        else if (qml[j] === "}" && --depth === 0) return qml.slice(start, j + 1);
    }
    throw new Error(`unbalanced braces in ${name}`);
}

const FNS = ["activeEntries", "geminiDeclaration", "openaiDeclaration", "renderDeclaration",
             "wrapDeclarations", "significantWords", "relevanceScore", "rankedEntries", "subsetForTurn"];

const strip = s => s
    .replace(/function (\w+)\(([^)]*)\): \w+/g, (_, n, a) => `function ${n}(${a})`)
    .replace(/(\w+): (string|int|var|real|bool)\b/g, "$1")
    .replace(/\broot\./g, "");

writeFileSync("./registry.mjs", strip(`
const emptyParameters = ${liftBlock("readonly property var emptyParameters:", "(", ")").slice(1, -1)};
const webToolsEnabled = true;
const agentToolEnabled = true;
const stopWords = ${liftBlock("readonly property var stopWords:", "(", ")").slice(1, -1)};
const entries = ${liftBlock("readonly property var entries:", "[", "]")};
${FNS.map(liftFn).join("\n")}
export { entries, subsetForTurn, rankedEntries, activeEntries, renderDeclaration, wrapDeclarations };
`).replace(/webToolsEnabled/g, "webToolsEnabled").replace(/agentToolEnabled/g, "agentToolEnabled"));

const R = await import("./registry.mjs");

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};

// The limit measured against gemma4-e4b on LiteRT-LM. Must match ModelRegistry.
const LIMIT = 1461;

// One per thing a user actually opens the assistant to do.
const TURNS = {
    "machine":  "what laptop is this, and how much RAM and disk does it have?",
    "web":      "search the web for the KOOMPI Ministation price",
    "page":     "read https://koompi.com/about and summarise it",
    "shell":    "run uptime and tell me the load average",
    "memory":   "remember that I prefer the helix editor",
    "namecall": "my name is Rithy, call me that from now on",
    "config":   "make the bar borderless in the shell config",
    "recall":   "what do you know about my editor preferences?",
    "chat":     "hey, what can you do?",
    "empty":    "",
};

const namesOf = (format, subset) => {
    const list = format === "gemini" ? subset[0].functionDeclarations : subset;
    return list.map(d => format === "gemini" ? d.name : d.function.name);
};

const seen = new Set();
const rows = [];
for (const format of ["openai", "gemini"]) {
    for (const [label, text] of Object.entries(TURNS)) {
        const subset = R.subsetForTurn(format, LIMIT, text);
        const bytes = JSON.stringify(subset).length;
        const names = namesOf(format, subset);
        check(`${format}/${label} stays under the ceiling`, bytes <= LIMIT, `${bytes} > ${LIMIT}`);
        check(`${format}/${label} carries the core tool`, names.includes("recall"), names.join(","));
        check(`${format}/${label} is not empty`, names.length > 0);
        if (format === "openai") {
            names.forEach(n => seen.add(n));
            rows.push({ label, bytes, names });
        }
    }
}

// Nothing may be permanently unreachable: every enabled tool has to be in reach of
// at least one of the turns a user would actually type.
const all = R.activeEntries("openai").map(e => e.name);
const unreachable = all.filter(n => !seen.has(n));
check("every tool is reachable from some turn", unreachable.length === 0, `unreachable: ${unreachable}`);

// The ranking has to be doing real work, not just returning the static prior.
const machine = namesOf("openai", R.subsetForTurn("openai", LIMIT, TURNS.machine));
const web = namesOf("openai", R.subsetForTurn("openai", LIMIT, TURNS.web));
const config = namesOf("openai", R.subsetForTurn("openai", LIMIT, TURNS.config));
check("a machine question reaches the agent", machine.includes("ask_agent"), machine.join(","));
check("a search reaches search_web", web.includes("search_web"), web.join(","));
check("a config change reaches set_shell_config", config.includes("set_shell_config"), config.join(","));
check("the subset actually varies by turn", JSON.stringify(machine) !== JSON.stringify(config),
    machine.join(","));

// A model with no measured ceiling is not subsetted at all.
const unlimited = namesOf("openai", R.subsetForTurn("openai", 0, TURNS.chat));
check("budget 0 keeps every tool", unlimited.length === all.length, `${unlimited.length} of ${all.length}`);

// A budget too small for anything must not produce a malformed array.
const starved = R.subsetForTurn("openai", 10, TURNS.chat);
check("an impossible budget yields an empty array", Array.isArray(starved) && starved.length === 0,
    JSON.stringify(starved));

if (process.env.DUMP_DIR) {
    mkdirSync(process.env.DUMP_DIR, { recursive: true });
    for (const [label, text] of Object.entries(TURNS)) {
        writeFileSync(`${process.env.DUMP_DIR}/${label}.json`,
            JSON.stringify(R.subsetForTurn("openai", LIMIT, text)));
    }
    console.log(rows.map(r => `${r.label.padEnd(9)} ${String(r.bytes).padStart(5)}B  ${r.names.join(" ")}`).join("\n"));
}

if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("ok: per-turn tool subsetting");
EOF

cd "$tmp" && DUMP_DIR="${DUMP_DIR:-}" bun run run.mjs "$REGISTRY" || fail=1

exit "$fail"
