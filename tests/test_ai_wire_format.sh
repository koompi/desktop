#!/usr/bin/env bash
# The OpenAI tool-calling wire format, asserted against the request body the shipped
# code actually builds. Runs the real functions out of OpenAiApiStrategy.qml against a
# captured LiteRT-LM tool-call stream: no mock strategy, no hand-written body. Prints
# the body it built so it can be read. No network.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML_DIR="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai"
STRATEGY="$QML_DIR/OpenAiApiStrategy.qml"
RUNNER="$QML_DIR/ToolRunner.qml"
REGISTRY="$QML_DIR/ToolRegistry.qml"

for f in "$STRATEGY" "$RUNNER" "$REGISTRY"; do
    [[ -f "$f" ]] || { echo "missing $f" >&2; exit 1; }
done
command -v bun >/dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

fail=0

# The id the model is answered with is minted in the strategy and stamped onto the
# result message by the runner. The test builds the body from the strategy's ids, so
# the runner has to still be reading them from the same place.
grep -q 'message.toolCallId = root._currentCallId' "$RUNNER" \
    || { echo "FAIL: ToolRunner no longer keys a tool result by the running call's id" >&2; fail=1; }
grep -q 'message.role = "tool"' "$RUNNER" \
    || { echo "FAIL: ToolRunner no longer gives a tool result the tool role" >&2; fail=1; }
grep -q 'root._currentCallId = call.id' "$RUNNER" \
    || { echo "FAIL: ToolRunner no longer tracks the id of the call it is running" >&2; fail=1; }

# Every tool carries the risk and approval the approval surface renders (D05, D06).
python3 - "$REGISTRY" <<'PY' || fail=1
import re, sys
src = open(sys.argv[1]).read()
start = src.index("readonly property var entries:")
depth, i = 0, src.index("[", start)
for j in range(i, len(src)):
    if src[j] == "[": depth += 1
    elif src[j] == "]":
        depth -= 1
        if depth == 0:
            end = j + 1
            break
block = src[i:end]
# One slice per entry, so the fields may sit in any order within it.
starts = [m.start() for m in re.finditer(r'^\s{12}"name": "\w+",', block, re.M)]
RISKS = {"safe", "reads-system", "writes-system", "leaves-machine"}
ok = bool(starts)
if not starts:
    print("FAIL: no tool entries found", file=sys.stderr)
by = {}
for i, s in enumerate(starts):
    chunk = block[s:starts[i + 1] if i + 1 < len(starts) else len(block)]
    name = re.search(r'"name": "(\w+)"', chunk).group(1)
    risk = re.search(r'"risk": "([a-z-]+)"', chunk)
    approval = re.search(r'"approval": "(never|once|always)"', chunk)
    priority = re.search(r'"priority": (\d+)', chunk)
    if not (risk and approval and priority):
        print(f"FAIL: {name} is missing risk, approval or priority", file=sys.stderr); ok = False
        continue
    if risk.group(1) not in RISKS:
        print(f"FAIL: {name} has risk {risk.group(1)!r}", file=sys.stderr); ok = False
    by[name] = risk.group(1)
for n, want in (("ask_agent", "leaves-machine"), ("run_shell_command", "writes-system")):
    if by.get(n) != want:
        print(f"FAIL: {n} risk is {by.get(n)}, expected {want}", file=sys.stderr); ok = False
sys.exit(0 if ok else 1)
PY

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
    let depth = 0;
    for (let j = qml.indexOf("{", start); j < qml.length; j++) {
        if (qml[j] === "{") depth++;
        else if (qml[j] === "}" && --depth === 0) return qml.slice(start, j + 1);
    }
    throw new Error(`unbalanced braces in ${name}`);
}

const strip = s => s
    .replace(/function (\w+)\(([^)]*)\): \w+/g, (_, n, a) => `function ${n}(${a})`)
    .replace(/(\w+): (AiModel|string|real|list<var>|AiMessageData)/g, "$1");

writeFileSync("./strategy.mjs", strip(`
let isReasoning = false;
let pendingToolCalls = {};
let toolCallEmitted = false;
${lift("takeCompletedToolCalls")}
${lift("wireMessage")}
${lift("buildRequestData")}
${lift("buildAuthorizationHeader")}
${lift("parseResponseLine")}
export { parseResponseLine, buildRequestData, buildAuthorizationHeader };
export function reset() { isReasoning = false; pendingToolCalls = {}; toolCallEmitted = false; }
`));

const { parseResponseLine, buildRequestData, buildAuthorizationHeader, reset } = await import("./strategy.mjs");

let failed = 0;
const check = (name, cond, extra = "") => {
    if (!cond) { console.error(`FAIL: ${name} ${extra}`); failed++; }
};

const msg = (over = {}) => Object.assign({
    role: "user", content: "", rawContent: "", functionName: "", functionResponse: "",
    toolCalls: [], toolCallId: "",
}, over);

// Verbatim shape from litert-lm 0.15.0 serving gemma4-e4b: two distinct calls in one
// turn, both stamped index 0 and both carrying the same id.
const stream = [
    'data: ' + JSON.stringify({ choices: [{ index: 0, delta: { tool_calls: [{ index: 0, id: "call_x_0", type: "function", function: { name: "run_shell_command", arguments: '{"command": "uptime"}' } }] } }] }),
    'data: ' + JSON.stringify({ choices: [{ index: 0, delta: { tool_calls: [{ index: 0, id: "call_x_0", type: "function", function: { name: "recall", arguments: '{"query": "editor"}' } }] } }] }),
    'data: ' + JSON.stringify({ choices: [{ index: 0, delta: {}, finish_reason: "tool_calls" }] }),
];

reset();
const assistant = msg({ role: "assistant" });
let calls = null;
for (const line of stream) {
    const r = parseResponseLine(line, assistant);
    if (r?.functionCalls) calls = r.functionCalls;
}

check("both calls came out of the stream", calls?.length === 2, `got ${calls?.length}`);
check("the ids are distinct", calls?.[0]?.id !== calls?.[1]?.id, JSON.stringify(calls?.map(c => c.id)));

// What ToolRunner.addToolResult builds: role "tool", keyed by the call it answers.
const results = (calls ?? []).map((c, i) => msg({
    role: "tool",
    functionName: c.name,
    functionResponse: i === 0 ? " 23:29:01 up 16:27,  load average: 2.90" : "- prefers helix",
    toolCallId: c.id,
    rawContent: "",
}));

const conversation = [
    msg({ role: "user", rawContent: "how long has this box been up, and what editor do i use?" }),
    assistant,
    ...results,
];

const local = { model: "gemma4-e4b", requires_key: false, extraParams: {} };
const body = buildRequestData(local, conversation, "You are a helpful assistant.", 0, [], "");
writeFileSync("./body.json", JSON.stringify(body, null, 2));

const wire = body.messages;
const asst = wire.find(m => m.tool_calls);
check("the assistant turn carries tool_calls", asst !== undefined);
check("it is an assistant turn", asst?.role === "assistant", asst?.role);
check("both calls ride on it", asst?.tool_calls?.length === 2, JSON.stringify(asst?.tool_calls));
for (const tc of asst?.tool_calls ?? []) {
    check(`call ${tc.id} is type function`, tc.type === "function", tc.type);
    check(`call ${tc.id} names a function`, (tc.function?.name ?? "").length > 0);
    check(`call ${tc.id} carries arguments as a string`, typeof tc.function?.arguments === "string", typeof tc.function?.arguments);
}

const toolTurns = wire.filter(m => m.role === "tool");
check("one tool message per call", toolTurns.length === 2, `got ${toolTurns.length}`);
const callIds = (asst?.tool_calls ?? []).map(c => c.id);
for (const t of toolTurns) {
    check(`tool message ${t.tool_call_id} matches a call`, callIds.includes(t.tool_call_id), `${t.tool_call_id} not in ${callIds}`);
    check(`tool message ${t.tool_call_id} carries the output`, (t.content ?? "").length > 0);
}
check("the tool messages follow the assistant turn",
    wire.indexOf(asst) < wire.indexOf(toolTurns[0]));
check("no role is left over as user plumbing",
    wire.filter(m => m.role === "user").length === 1, JSON.stringify(wire.map(m => m.role)));

const raw = JSON.stringify(body);
check("no [[ Function: ]] prose on the wire", !raw.includes("[[ Function"), raw.slice(0, 200));
check("no [[ Output of ]] prose on the wire", !raw.includes("[[ Output of"), raw.slice(0, 200));
check("an empty tool list is omitted, not sent as []", body.tools === undefined, JSON.stringify(body.tools));

// Without this LiteRT-LM streams no usage object at all and tokenCount stays -1
// forever, so compaction can never fire. Verified honoured against 127.0.0.1:9379.
check("usage is requested on the stream", body.stream_options?.include_usage === true,
    JSON.stringify(body.stream_options));

const withTools = buildRequestData(local, conversation, "sys", 0, [{ type: "function", function: { name: "recall" } }], "");
check("a non-empty tool list is sent", withTools.tools?.length === 1);

// D08: no bearer for a model that needs no key.
check("no Authorization header for a local model", buildAuthorizationHeader("API_KEY", local) === "",
    buildAuthorizationHeader("API_KEY", local));
check("an Authorization header for a model that needs a key",
    buildAuthorizationHeader("API_KEY", { requires_key: true }).includes("Authorization"));
check("no header when the model is missing entirely", buildAuthorizationHeader("API_KEY", undefined) === "");

// A chat saved before any of this existed has no ids; it must not claim the tool role.
const legacy = buildRequestData(local, [msg({ role: "tool", functionName: "recall", functionResponse: "- prefers helix" })], "sys", 0, [], "");
check("a tool message with no id degrades to user", legacy.messages[1].role === "user", legacy.messages[1].role);

if (process.env.SHOW_BODY === "1") console.log(JSON.stringify(body, null, 2));
if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("ok: openai tool-calling wire format");
EOF

cd "$tmp" && bun run run.mjs "$STRATEGY" || fail=1

exit "$fail"
