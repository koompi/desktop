#!/usr/bin/env bash
# LiteRT-LM stamps every tool call in a turn with index 0 and the same id, so a naive
# accumulator concatenates them into one call named "set_owner_nameremember". Runs the
# real functions out of OpenAiApiStrategy.qml against captured server output. No network.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
STRATEGY="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/OpenAiApiStrategy.qml"

[[ -f "$STRATEGY" ]] || { echo "missing $STRATEGY" >&2; exit 1; }
command -v bun >/dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/run.mjs" <<'EOF'
import { readFileSync, writeFileSync } from "node:fs";

const qml = readFileSync(process.argv[2], "utf8");

// Lift a function out of the .qml by brace matching, so the test runs the shipped
// source rather than a copy that can drift away from it.
function lift(name) {
    const start = qml.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} not found in OpenAiApiStrategy.qml`);
    let depth = 0, i = qml.indexOf("{", start);
    for (let j = i; j < qml.length; j++) {
        if (qml[j] === "{") depth++;
        else if (qml[j] === "}" && --depth === 0) return qml.slice(start, j + 1);
    }
    throw new Error(`unbalanced braces in ${name}`);
}

writeFileSync("./strategy.mjs", `
let isReasoning = false;
let pendingToolCalls = {};
let toolCallEmitted = false;
${lift("takeCompletedToolCall")}
${lift("parseResponseLine")}
export { parseResponseLine };
export function reset() { isReasoning = false; pendingToolCalls = {}; toolCallEmitted = false; }
`);

const { parseResponseLine, reset } = await import("./strategy.mjs");

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};

const chunk = (calls, finish = null) => "data: " + JSON.stringify({
    choices: [{ index: 0, delta: calls ? { tool_calls: calls } : {}, finish_reason: finish }]
});

// Verbatim shape from litert-lm 0.15.0 serving gemma4-e4b: two distinct calls, both
// index 0, both carrying the same id, each with a complete name and arguments.
const litertStream = [
    chunk([{ index: 0, id: "call_x_0", type: "function", function: { name: "set_owner_name", arguments: '{"name": "Rithy"}' } }]),
    chunk([{ index: 0, id: "call_x_0", type: "function", function: { name: "remember", arguments: '{"text": "User prefers dark mode."}' } }]),
    chunk(null, "tool_calls"),
];

reset();
let message = { content: "", rawContent: "", functionName: "" };
let result = null;
for (const line of litertStream) {
    const r = parseResponseLine(line, message);
    if (r?.functionCall) result = r.functionCall;
}

check("a call is emitted", result !== null);
check("names are not concatenated", result?.name === "set_owner_name", `got ${result?.name}`);
check("arguments parse", result?.args?.name === "Rithy", JSON.stringify(result?.args));
check("the skipped call is named for the model", message.rawContent.includes("remember"), message.rawContent);

// A well-behaved provider fragments arguments across deltas and increments index.
reset();
message = { content: "", rawContent: "", functionName: "" };
result = null;
for (const line of [
    chunk([{ index: 0, function: { name: "run_shell_command" } }]),
    chunk([{ index: 0, function: { arguments: '{"comm' } }]),
    chunk([{ index: 0, function: { arguments: 'and": "ls"}' } }]),
    chunk(null, "tool_calls"),
]) {
    const r = parseResponseLine(line, message);
    if (r?.functionCall) result = r.functionCall;
}

check("fragmented arguments reassemble", result?.args?.command === "ls", JSON.stringify(result?.args));
check("fragmented name survives", result?.name === "run_shell_command", `got ${result?.name}`);

if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("ok: tool call stream accumulation");
EOF

cd "$tmp" && bun run run.mjs "$STRATEGY"
