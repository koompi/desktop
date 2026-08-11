pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import qs.services
import "../../modules/koompi/sidebarLeft/aiChat/grounding.js" as Grounding
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The correction loop. `engine` is the Ai facade.
 *
 * Its first job is the one the live session exposed: a turn that says it stored
 * something, when nothing was stored. The check is made against the turn's tool
 * calls, never against its prose - the prose is only what raises the question.
 * What gets stored is read out of the *user's* sentence, because that is the
 * only text in the turn whose author knows the fact.
 *
 * Everything it writes carries `precedence: asserted`, and an asserted value is
 * never silently replaced by a later contradicting memory: the conflict is put
 * in front of the user instead.
 */
QtObject {
    id: root

    property QtObject engine

    readonly property string storeDir: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/ai/feedback`)
    readonly property string statePath: `${root.storeDir}/state.json`
    readonly property string proceduresPath: `${root.storeDir}/procedures.json`
    // 36:238 - the bundle is written here and never sent anywhere.
    readonly property string reportDir: CF.FileUtils.trimFileProtocol(`${Directories.home}/.local/share/koompi-ai/reports`)

    readonly property string precedence: "asserted"
    readonly property string correctionSource: "manual-correction"

    signal correctionApplied(var record)
    signal claimUnbacked(var audit)
    signal conflictRaised(var conflict)

    /* ------------------------------------------------------------------ *
     * State
     * ------------------------------------------------------------------ */

    property var corrections: []
    property var suppressed: []
    property var conflicts: []
    property var turns: []
    property double recallPausedUntil: 0
    property real groundingFloor: 0
    property var procedures: []
    property bool loaded: false

    readonly property bool recallPaused: root.recallPausedUntil > Date.now()
    readonly property int maxTurns: 500

    readonly property var activeCorrections: root.corrections.filter(c => c.active !== false && c.scope !== "once")

    /* ------------------------------------------------------------------ *
     * Pure rules. No QML type is reachable from here on purpose: the same
     * functions are lifted into node by tests/test_ai_correction.sh and run
     * against the observed transcript.
     * ------------------------------------------------------------------ */

    function clausesOf(text) {
        return String(text ?? "")
            .split(/[.!?;\n]+/)
            .map(clause => clause.trim())
            .filter(clause => clause.length > 0);
    }

    function contentWords(text) {
        const stop = ["that", "this", "with", "from", "they", "them", "have", "been", "their", "about",
            "when", "what", "which", "would", "there", "into", "your", "yours", "also", "than", "then",
            "some", "more", "very", "just", "user", "will", "does", "like", "want", "wants", "always",
            "never", "call", "name"];
        const words = String(text ?? "").toLowerCase().match(/[a-z0-9][a-z0-9'-]{3,}/g) ?? [];
        const out = [];
        for (const word of words) {
            if (stop.indexOf(word) >= 0) continue;
            if (out.indexOf(word) < 0) out.push(word);
        }
        return out;
    }

    function keyWord(text) {
        const words = root.contentWords(text);
        return words.length > 0 ? words[0] : "";
    }

    function overlaps(a, b) {
        const left = root.contentWords(a);
        const right = root.contentWords(b);
        if (left.length === 0 || right.length === 0) return false;
        let hits = 0;
        for (const word of left) if (right.indexOf(word) >= 0) hits++;
        return hits >= Math.min(2, Math.min(left.length, right.length));
    }

    function normalise(value) {
        return String(value ?? "")
            .toLowerCase()
            .replace(/[*_`"'.,!?]/g, "")
            .replace(/^(?:the|a|an)\s+/, "")
            .replace(/\s+/g, " ")
            .trim();
    }

    function sameValue(a, b) {
        const left = root.normalise(a);
        const right = root.normalise(b);
        if (left.length === 0 || right.length === 0) return false;
        return left === right || left.indexOf(right) >= 0 || right.indexOf(left) >= 0;
    }

    // A name is one or two plain words. Anything that opens with a verb or a
    // filler is a sentence about the user, not the user's name.
    function nameToken(rest) {
        const match = /^([A-Za-z][A-Za-z'-]*(?:\s+[A-Za-z][A-Za-z'-]*)?)/.exec(String(rest ?? "").trim());
        if (!match) return "";
        const words = match[1].split(/\s+/);
        const notNames = ["not", "no", "a", "an", "the", "going", "trying", "looking", "working", "sorry",
            "sure", "using", "asking", "here", "just", "fine", "ok", "okay", "good", "done", "tired",
            "confused", "from", "in", "on", "at", "your", "my", "his", "her", "still", "so",
            "very", "really", "afraid", "glad", "happy", "back", "curious", "new", "old", "about"];
        if (notNames.indexOf(words[0].toLowerCase()) >= 0) return "";
        if (words.length === 2) {
            if (notNames.indexOf(words[1].toLowerCase()) >= 0) return words[0];
            // "Rithy Thul" is a name; "Rithy and" is one name and a conjunction
            if (!/^[A-Z]/.test(words[1])) return words[0];
        }
        return words.join(" ");
    }

    // The whole point of the job, in one function. "i am not Nimmit. You are
    // Nimmit. I am Rithy." has to yield Rithy: the negated clause is dropped,
    // the clause about the assistant is dropped, and the last claim wins.
    function ownerNameFrom(text) {
        let found = "";
        for (const clause of root.clausesOf(text)) {
            if (/^(?:and\s+|but\s+|so\s+|no,?\s+|actually,?\s+)?(?:you|your)\b/i.test(clause)) continue;
            const match = /^(?:and\s+|but\s+|so\s+|no,?\s+|actually,?\s+|hey,?\s+)?(?:i['’]m|im|i\s+am|my\s+name\s+is|my\s+name['’]s|call\s+me|i\s+go\s+by)\b\s+(.+)$/i.exec(clause);
            if (!match) continue;
            let rest = match[1].trim();
            if (/^(?:not|never)\b/i.test(rest)) continue;
            rest = rest.replace(/^(?:actually|really|still)\s+/i, "");
            const name = root.nameToken(rest);
            if (name.length > 0) found = name;
        }
        return found;
    }

    function capitalise(text) {
        const value = String(text ?? "").trim();
        if (value.length === 0) return value;
        return value.charAt(0).toUpperCase() + value.slice(1);
    }

    function asStatement(text) {
        const value = String(text ?? "").trim().replace(/\s+/g, " ");
        if (value.length === 0) return "";
        return /[.!?]$/.test(value) ? root.capitalise(value) : root.capitalise(value) + ".";
    }

    // What the user's own turn asserts, if anything. Precision over recall, the
    // same trade memd's extractor makes: a rule that is not certain returns null
    // and the turn is left alone.
    function correctionFrom(userText) {
        const name = root.ownerNameFrom(userText);
        if (name.length > 0) {
            return {
                "kind": "owner-name",
                "value": name,
                "statement": `The user's name is ${name}.`,
                "mtype": "identity",
                "subject": "owner.name"
            };
        }
        for (const clause of root.clausesOf(userText)) {
            let match = /^(?:and\s+|but\s+|so\s+)?from\s+now\s+on,?\s+(.+)$/i.exec(clause);
            if (match) {
                const body = match[1].trim();
                return {
                    "kind": "instruction",
                    "value": body,
                    "statement": root.asStatement(`From now on ${body}`),
                    "mtype": "instruction",
                    "subject": `instruction.${root.keyWord(body)}`
                };
            }
            match = /^(?:and\s+|but\s+|so\s+)?(always|never)\s+(.+)$/i.exec(clause);
            if (match) {
                const body = `${match[1].toLowerCase()} ${match[2].trim()}`;
                return {
                    "kind": "instruction",
                    "value": body,
                    "statement": root.asStatement(body),
                    "mtype": "instruction",
                    "subject": `instruction.${root.keyWord(match[2])}`
                };
            }
            match = /^(?:and\s+|but\s+|so\s+)?i\s+(?:prefer|would\s+rather|['’]d\s+rather)\s+(.+)$/i.exec(clause);
            if (match) {
                const body = match[1].trim();
                return {
                    "kind": "preference",
                    "value": body,
                    "statement": `The user prefers ${body}.`,
                    "mtype": "preference",
                    "subject": `user.prefers.${root.keyWord(body)}`
                };
            }
            match = /^(?:and\s+|but\s+|so\s+)?remember\s+that\s+(.+)$/i.exec(clause);
            if (match) {
                const body = match[1].trim();
                return {
                    "kind": "fact",
                    "value": body,
                    "statement": root.asStatement(body),
                    "mtype": "fact",
                    "subject": root.subjectOf(root.asStatement(body)).subject
                };
            }
        }
        return null;
    }

    // Prose only ever raises the question. It never decides what is stored and
    // it never decides whether something was stored.
    function claimsStorage(assistantText) {
        const text = String(assistantText ?? "").toLowerCase();
        const claims = [
            /\bi(?:['’]ve| have)\s+(?:now\s+)?(?:noted|saved|stored|updated|remembered|recorded)\b/,
            /\b(?:noted|saved|stored|updated)\s+(?:that|it|this)\b/,
            /\bi(?:['’]ll| will)\s+(?:call you|remember|keep that in mind|make sure to call)\b/,
            /\bsaved\s+(?:that|it|this)\s+to\s+(?:my\s+)?(?:long[- ]term\s+)?memory\b/,
            /\bgot\s+it\b/,
            /\bconsider\s+it\s+(?:done|noted)\b/,
            /\bwon['’]t\s+forget\b/,
            /\bfrom\s+now\s+on\b/,
            /\bi(?:['’]ll| will)\s+use\s+.{0,20}\bfrom\s+now\s+on\b/
        ];
        for (const claim of claims) if (claim.test(text)) return true;
        return false;
    }

    function callArgs(call) {
        if (!call) return ({});
        if (call.args && typeof call.args === "object") return call.args;
        try {
            const parsed = JSON.parse(call.arguments ?? "{}");
            return (parsed && typeof parsed === "object") ? parsed : ({});
        } catch (e) {
            return ({});
        }
    }

    function storageCalls(calls) {
        return (Array.isArray(calls) ? calls : [])
            .filter(call => call?.name === "set_owner_name" || call?.name === "remember");
    }

    // The record, not the prose. A correction is backed only by a call that
    // carries the same value the user gave.
    function backingCall(calls, correction) {
        if (!correction) return null;
        for (const call of (Array.isArray(calls) ? calls : [])) {
            const name = call?.name ?? "";
            const args = root.callArgs(call);
            if (correction.kind === "owner-name") {
                if (name !== "set_owner_name") continue;
                if (root.sameValue(args.name, correction.value)) return call;
                continue;
            }
            if (name !== "remember") continue;
            if (root.overlaps(args.text ?? "", correction.statement)) return call;
        }
        return null;
    }

    function auditTurn(turn) {
        const calls = turn?.toolCalls ?? [];
        const correction = root.correctionFrom(turn?.userText ?? "");
        const claimed = root.claimsStorage(turn?.assistantText ?? "");
        if (!correction) {
            return {
                "verdict": (claimed && root.storageCalls(calls).length === 0) ? "claim-without-call" : "none",
                "claimed": claimed,
                "correction": null,
                "backing": null
            };
        }
        const backing = root.backingCall(calls, correction);
        if (backing) return { "verdict": "ok", "claimed": claimed, "correction": correction, "backing": backing };
        return {
            "verdict": claimed ? "unbacked-claim" : "silent-drop",
            "claimed": claimed,
            "correction": correction,
            "backing": null
        };
    }

    // The subject a statement is about, so a later statement about the same
    // subject can be recognised as a contradiction rather than an addition.
    function subjectOf(statement) {
        const text = String(statement ?? "").trim().toLowerCase().replace(/[.!]+$/, "");
        let match = /^the\s+user['’]?s?\s+name\s+is\s+(.+)$/.exec(text);
        if (match) return { "subject": "owner.name", "value": match[1].trim() };
        match = /^the\s+user['’]s\s+([a-z][a-z -]*?)\s+is\s+(.+)$/.exec(text);
        if (match) return { "subject": `user.${match[1].trim().replace(/\s+/g, "-")}`, "value": match[2].trim() };
        match = /^the\s+user\s+prefers\s+(.+)$/.exec(text);
        if (match) return { "subject": `user.prefers.${root.keyWord(match[1])}`, "value": match[1].trim() };
        match = /^(?:always|never|from\s+now\s+on)\s+(.+)$/.exec(text);
        if (match) return { "subject": `instruction.${root.keyWord(match[1])}`, "value": text };
        return { "subject": "", "value": text };
    }

    function contradicts(assertedSubject, assertedValue, statement) {
        const incoming = root.subjectOf(statement);
        if (incoming.subject.length === 0) return false;
        if (incoming.subject !== assertedSubject) return false;
        return !root.sameValue(incoming.value, assertedValue);
    }

    /* ---- the habit table (docs/neuromorphic-memory-design.md:224-247) ---- */

    function procedureKey(name, args) {
        const values = args ?? ({});
        if (name === "run_shell_command") {
            const command = String(values.command ?? "").trim();
            if (command.length === 0) return "*";
            const meta = [";", "|", "&", ">", "<", "\n", "$(", "`"];
            for (const character of meta) if (command.indexOf(character) >= 0) return "compound";
            return command.split(/\s+/)[0];
        }
        if (name === "remember") return String(values.type ?? "fact");
        if (name === "set_shell_config" || name === "get_shell_config") return String(values.key ?? "*").split(".")[0];
        if (name === "fetch_url") {
            const host = /^[a-z]+:\/\/([^\/?#]+)/i.exec(String(values.url ?? ""));
            return host ? host[1].toLowerCase() : "*";
        }
        if (name === "recall" || name === "search_web") return "query";
        if (name === "ask_agent") return "task";
        return "*";
    }

    function outcomeOf(name, response) {
        const text = String(response ?? "");
        if (text.trim().length === 0) return "failure";
        if (/\[\[ Command exited with code [1-9][0-9]* /.test(text)) return "failure";
        if (/^\s*Invalid arguments/i.test(text)) return "failure";
        if (/^\s*No such tool/i.test(text)) return "failure";
        if (/rejected by user|declined to run the agent/i.test(text)) return "failure";
        if (/is unavailable right now|returned nothing|is disabled in the shell config|already (?:working on|in progress)/i.test(text)) return "failure";
        return "success";
    }

    // 3.6 characters per token is the ratio Conversation.qml estimates with. It
    // is an estimate and the column says so.
    function estimateTokens(text) {
        return Math.round(String(text ?? "").length / 3.6);
    }

    /* ------------------------------------------------------------------ *
     * Watching turns
     * ------------------------------------------------------------------ */

    property string _lastAuditedId: ""
    property int _settleTries: 0

    // `responseFinished` fires from the stream, while curl is still up and the
    // tool calls of the turn have not run yet. The audit waits for the turn to
    // actually settle instead.
    readonly property Timer settleTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: root.observeTurn()
    }

    readonly property Connections engineWatch: Connections {
        target: root.engine
        function onResponseFinished() {
            root._settleTries = 0;
            root.settleTimer.restart();
        }
        // A turn that ends by timing out, or by being cancelled, never reaches
        // `responseFinished`. The engine going idle is the other way in.
        function onRequestActiveChanged() {
            if (root.engine?.requestActive) return;
            root._settleTries = 0;
            root.settleTimer.restart();
        }
    }

    // Everything since the last thing the user typed: what they said, what the
    // assistant said back, every call it made and every result it got.
    function currentTurn() {
        const conversation = root.engine?.conversation;
        if (!conversation) return null;
        const ids = conversation.messageIDs ?? [];
        const after = [];
        let userText = "";
        for (let i = ids.length - 1; i >= 0; i--) {
            const message = conversation.messageByID[ids[i]];
            if (!message) continue;
            if (message.role === "user" && (message.toolCallId ?? "").length === 0) {
                userText = message.rawContent || message.content || "";
                break;
            }
            after.unshift({ "id": ids[i], "message": message });
        }

        const turn = {
            "userText": userText,
            "assistantText": "",
            "toolCalls": [],
            "toolResults": [],
            "sources": [],
            "messageId": "",
            "done": false,
            "pending": false
        };
        for (const entry of after) {
            const message = entry.message;
            const isToolResult = message.role === "tool" || (message.toolCallId ?? "").length > 0;
            if (isToolResult) {
                turn.toolResults.push({
                    "toolCallId": message.toolCallId ?? "",
                    "name": message.functionName ?? "",
                    "response": message.functionResponse ?? message.content ?? ""
                });
                continue;
            }
            if (message.role !== "assistant") continue;
            turn.assistantText += (turn.assistantText.length > 0 ? "\n" : "") + (message.content ?? "");
            turn.toolCalls = turn.toolCalls.concat(message.toolCalls ?? []);
            turn.sources = message.sources ?? [];
            turn.messageId = entry.id;
            turn.done = message.done ?? false;
            if (message.functionPending) turn.pending = true;
        }
        return turn;
    }

    function observeTurn() {
        const turn = root.currentTurn();
        if (!turn || turn.messageId.length === 0) return;
        // Waiting on an approval click is not a settled turn, and it ends in
        // another response, which re-arms this by itself.
        if (turn.pending) return;
        if (!turn.done || root.engine?.requestActive) {
            if (root._settleTries++ < 120) root.settleTimer.restart();
            return;
        }
        if (turn.messageId === root._lastAuditedId) return;
        root._lastAuditedId = turn.messageId;

        root.recordProcedures(turn);
        root.recordTurn(turn);

        const audit = root.auditTurn(turn);
        if (audit.verdict === "unbacked-claim" || audit.verdict === "silent-drop") {
            root.claimUnbacked({ "audit": audit, "turn": turn });
            root.repair(audit, turn);
        }
        root.scanForConflicts();
    }

    function repair(audit, turn) {
        const correction = audit.correction;
        const alreadyRight = correction.kind === "owner-name"
            && root.sameValue(root.engine?.ownerName ?? "", correction.value)
            && root.activeCorrections.some(entry => entry.subject === "owner.name" && root.sameValue(entry.value, correction.value));
        if (alreadyRight) return;

        root.applyCorrection({
            "kind": correction.kind,
            "value": correction.value,
            "statement": correction.statement,
            "mtype": correction.mtype,
            "subject": correction.subject,
            "claim": (turn.assistantText ?? "").split("\n")[0].slice(0, 200),
            "scope": "durable",
            "origin": audit.verdict === "unbacked-claim" ? "auto-repair-after-claim" : "auto-repair",
            "messageId": turn.messageId
        }, (record, error) => {
            const said = audit.verdict === "unbacked-claim"
                ? Translation.tr("I said I had noted that, and I had not. Stored now: %1").arg(record.statement)
                : Translation.tr("Stored, so it outlasts this conversation: %1").arg(record.statement);
            const tail = error && error.length > 0
                ? Translation.tr(" (memory refused it: %1)").arg(error)
                : "";
            root.engine.addMessage(said + tail, root.engine.interfaceRole);
        });
    }

    /* ------------------------------------------------------------------ *
     * Writing a correction
     * ------------------------------------------------------------------ */

    // What the modal shows before it writes anything. Same object the write uses.
    function provenanceOf(record) {
        return {
            "store": Translation.tr("the assistant's memory store"),
            "statement": record?.statement ?? "",
            "mtype": record?.mtype ?? "fact",
            "precedence": root.precedence,
            "source": root.correctionSource,
            "tags": root.tagsFor(record),
            "durable": (record?.scope ?? "durable") !== "once"
        };
    }

    function tagsFor(record) {
        const tags = ["asserted", `precedence:${root.precedence}`];
        const subject = record?.subject ?? "";
        if (subject.length > 0) tags.push(`subject:${subject}`);
        return tags;
    }

    function applyCorrection(input, callback) {
        const record = {
            "id": `corr-${Date.now()}-${root.corrections.length}`,
            "kind": input.kind ?? "fact",
            "value": input.value ?? "",
            "statement": input.statement ?? "",
            "mtype": input.mtype ?? "fact",
            "subject": input.subject ?? "",
            "claim": input.claim ?? "",
            "scope": input.scope ?? "durable",
            "origin": input.origin ?? "user-modal",
            "precedence": root.precedence,
            "source": root.correctionSource,
            "sessionId": root.engine?.sessionId ?? "",
            "messageId": input.messageId ?? "",
            "at": Date.now(),
            "memoryId": -1,
            "memoryError": "",
            "active": true
        };

        // The name is shell state, not a memory, and it is what {OWNER} reads.
        if (record.kind === "owner-name" && root.engine?.setOwnerName) root.engine.setOwnerName(record.value);

        root.corrections = [...root.corrections, record];
        root.markCorrected(record);
        root.save();

        if (record.scope === "once") {
            root.correctionApplied(record);
            if (callback) callback(record, "");
            return record;
        }

        MemoryService.remember(record.statement, record.mtype, root.tagsFor(record), root.correctionSource, (response, error) => {
            const index = root.corrections.findIndex(entry => entry.id === record.id);
            if (index >= 0) {
                const updated = root.corrections.slice();
                updated[index] = Object.assign({}, updated[index], {
                    "memoryId": response?.memory_id ?? -1,
                    "memoryError": error ?? ""
                });
                root.corrections = updated;
                root.save();
            }
            root.correctionApplied(record);
            if (callback) callback(record, error ?? "");
        });
        return record;
    }

    function markCorrected(record) {
        if (!record.messageId) return;
        const index = root.turns.findIndex(entry => entry.messageId === record.messageId);
        if (index < 0) return;
        const updated = root.turns.slice();
        updated[index] = Object.assign({}, updated[index], { "corrected": true });
        root.turns = updated;
    }

    /* ---- the modal ---- */

    property bool correctionOpen: false
    property var pendingCorrection: null

    // What the user's last turn already said, so the modal opens knowing it
    // rather than asking them to type it a second time.
    function suggestionFrom() {
        const correction = root.correctionFrom(root.currentTurn()?.userText ?? "");
        return correction ? correction.statement : "";
    }

    // `target` is {claim, messageId, source} - the answer or one citation row.
    function openCorrection(target) {
        root.pendingCorrection = {
            "claim": target?.claim ?? "",
            "messageId": target?.messageId ?? "",
            "source": target?.source ?? null,
            "suggested": target?.suggested ?? root.suggestionFrom()
        };
        root.correctionOpen = true;
    }

    function closeCorrection() {
        root.correctionOpen = false;
        root.pendingCorrection = null;
    }

    // Types a typed correction without asking the user to pick one.
    function draftFrom(text, claim) {
        const value = String(text ?? "").trim();
        if (value.length === 0) return null;
        const fromRules = root.correctionFrom(value);
        if (fromRules) {
            return Object.assign({}, fromRules, { "claim": claim ?? "" });
        }
        const name = /^(?:my\s+name\s+is\s+)?([A-Z][A-Za-z'-]*)$/.exec(value);
        if (name) {
            return {
                "kind": "owner-name",
                "value": name[1],
                "statement": `The user's name is ${name[1]}.`,
                "mtype": "identity",
                "subject": "owner.name",
                "claim": claim ?? ""
            };
        }
        const statement = root.asStatement(value);
        const subject = root.subjectOf(statement);
        let mtype = "fact";
        if (/^(?:always|never|from now on)\b/i.test(statement)) mtype = "instruction";
        else if (/\bprefers?\b/i.test(statement)) mtype = "preference";
        else if (/^the user['’]?s?\s+name\s+is\b/i.test(statement)) mtype = "identity";
        return {
            "kind": mtype === "identity" ? "owner-name" : mtype,
            "value": subject.value,
            "statement": statement,
            "mtype": mtype,
            "subject": subject.subject,
            "claim": claim ?? ""
        };
    }

    /* ------------------------------------------------------------------ *
     * A correction outranks inference
     * ------------------------------------------------------------------ */

    property double _lastConflictScan: 0

    function scanForConflicts() {
        if (root.activeCorrections.length === 0) return;
        if (Date.now() - root._lastConflictScan < 30000) return;
        root._lastConflictScan = Date.now();
        MemoryService.list(200, (response, error) => {
            if (!response) return;
            root.checkAgainst(response.results ?? []);
        });
    }

    // An asserted value is never rewritten by what arrives later. The later row
    // keeps existing; what changes is that the user is told the two disagree.
    function checkAgainst(rows) {
        const raised = [];
        for (const correction of root.activeCorrections) {
            if (correction.subject.length === 0) continue;
            for (const row of rows) {
                if (row.source === root.correctionSource) continue;
                if (row.id === correction.memoryId) continue;
                if (!root.contradicts(correction.subject, correction.value, row.text ?? "")) continue;
                const key = `${correction.id}:${row.id}`;
                if (root.conflicts.some(entry => entry.key === key)) continue;
                raised.push({
                    "key": key,
                    "subject": correction.subject,
                    "asserted": correction.statement,
                    "assertedAt": correction.at,
                    "incoming": row.text ?? "",
                    "incomingId": row.id,
                    "incomingSource": row.source ?? "",
                    "at": Date.now(),
                    "resolved": false
                });
            }
        }
        if (raised.length === 0) return;
        root.conflicts = [...root.conflicts, ...raised];
        root.save();
        for (const conflict of raised) {
            root.conflictRaised(conflict);
            root.engine.addMessage(
                Translation.tr("You told me: %1\nSomething else in my memory says: %2\nI am keeping what you told me. Open the correction panel to drop the other one.")
                    .arg(conflict.asserted).arg(conflict.incoming),
                root.engine.interfaceRole);
        }
    }

    function resolveConflict(key, dropIncoming) {
        const index = root.conflicts.findIndex(entry => entry.key === key);
        if (index < 0) return;
        const conflict = root.conflicts[index];
        const updated = root.conflicts.slice();
        updated[index] = Object.assign({}, conflict, { "resolved": true, "resolvedAt": Date.now() });
        root.conflicts = updated;
        root.save();
        if (dropIncoming && conflict.incomingId >= 0) MemoryService.forget(conflict.incomingId, null);
    }

    readonly property var openConflicts: root.conflicts.filter(entry => !entry.resolved)

    /* ------------------------------------------------------------------ *
     * Suppression: excluded from retrieval, never deleted
     * ------------------------------------------------------------------ */

    function sourceKey(source) {
        const type = String(source?.type ?? "memory");
        const identity = String(source?.url ?? "").length > 0 ? source.url : String(source?.name ?? "");
        return `${type}|${root.normalise(identity)}`;
    }

    function suppressSource(source) {
        const key = root.sourceKey(source);
        if (root.suppressed.some(entry => entry.key === key && entry.active)) return;
        // A memory row's id is the exact handle; the name is a truncated copy of
        // its text, so resolve it while the recall that produced it is still here.
        let memoryId = -1;
        if ((source?.type ?? "") === "memory") {
            const rows = MemoryService.lastRecall ?? [];
            const wanted = String(source?.name ?? "").replace(/…$/, "");
            for (const row of rows) {
                if (String(row.text ?? "").indexOf(wanted) === 0) { memoryId = row.id; break; }
            }
        }
        root.suppressed = [...root.suppressed, {
            "key": key,
            "type": source?.type ?? "memory",
            "name": source?.name ?? "",
            "detail": source?.detail ?? "",
            "url": source?.url ?? "",
            "memoryId": memoryId,
            "at": Date.now(),
            "active": true
        }];
        root.save();
    }

    function unsuppressSource(key) {
        const index = root.suppressed.findIndex(entry => entry.key === key);
        if (index < 0) return;
        const updated = root.suppressed.slice();
        updated[index] = Object.assign({}, updated[index], { "active": false, "liftedAt": Date.now() });
        root.suppressed = updated;
        root.save();
    }

    function isSourceSuppressed(source) {
        const key = root.sourceKey(source);
        return root.suppressed.some(entry => entry.key === key && entry.active);
    }

    function isMemorySuppressed(row) {
        const text = String(row?.text ?? "");
        for (const entry of root.suppressed) {
            if (!entry.active || entry.type !== "memory") continue;
            if (entry.memoryId >= 0 && entry.memoryId === row?.id) return true;
            const name = String(entry.name ?? "").replace(/…$/, "");
            if (name.length > 0 && text.indexOf(name) === 0) return true;
        }
        return false;
    }

    // The losing side of an open conflict. It is not deleted and it is still in
    // the browser; it just stops being read into the prompt, which is what
    // "a correction outranks inference" has to mean at retrieval time.
    function losesConflict(row, conflicts) {
        for (const conflict of (conflicts ?? [])) {
            if (conflict.resolved) continue;
            if (conflict.incomingId === row?.id) return true;
        }
        return false;
    }

    // What the turn is allowed to be given. Suppression, the pause and a lost
    // conflict all land here, so nothing has to be deleted for any of them.
    function filterRecall(results) {
        const rows = Array.isArray(results) ? results : [];
        if (root.recallPaused) return [];
        return rows.filter(row => !root.isMemorySuppressed(row) && !root.losesConflict(row, root.conflicts));
    }

    readonly property var activeSuppressions: root.suppressed.filter(entry => entry.active)

    /* ------------------------------------------------------------------ *
     * Measuring whether any of this is working
     * ------------------------------------------------------------------ */

    readonly property int windowDays: 7
    readonly property int minTurnsForGap: 10
    readonly property int minCorrectionsForGap: 2

    // What the turn was actually given. `message.sources` currently carries only
    // what the tools of the turn returned; the memories recalled for it are
    // published separately until the producer appends them, and they fed the
    // answer just as much, so the measurement counts both.
    function sourcesOf(turn) {
        return MemoryService.withMemorySources(turn?.sources ?? []);
    }

    function recordTurn(turn) {
        const grounding = Grounding.computeGrounding(root.sourcesOf(turn), turn.assistantText ?? "");
        const entry = {
            "messageId": turn.messageId,
            "sessionId": root.engine?.sessionId ?? "",
            "at": Date.now(),
            "grounding": grounding ? grounding.value : null,
            "sourceCount": root.sourcesOf(turn).length,
            "corrected": false
        };
        const kept = [...root.turns, entry];
        root.turns = kept.length > root.maxTurns ? kept.slice(kept.length - root.maxTurns) : kept;
        root.save();
    }

    readonly property var trustReport: {
        const since = Date.now() - root.windowDays * 86400000;
        const window = root.turns.filter(entry => entry.at >= since);
        const grounded = window.filter(entry => entry.grounding !== null && entry.grounding !== undefined);
        const corrections = root.corrections.filter(entry => entry.at >= since);
        const correctedGrounded = grounded.filter(entry => entry.corrected).length;

        const stated = grounded.length > 0
            ? grounded.reduce((sum, entry) => sum + entry.grounding, 0) / grounded.length
            : null;
        const measured = grounded.length > 0 ? 1 - correctedGrounded / grounded.length : null;
        const enough = grounded.length >= root.minTurnsForGap && corrections.length >= root.minCorrectionsForGap;

        return {
            "windowDays": root.windowDays,
            "turns": window.length,
            "groundedTurns": grounded.length,
            "corrections": corrections.length,
            "autoRepairs": corrections.filter(entry => String(entry.origin ?? "").indexOf("auto-repair") === 0).length,
            "correctedTurns": correctedGrounded,
            "statedGrounding": stated,
            "measuredAccuracy": measured,
            "gap": (enough && stated !== null && measured !== null) ? stated - measured : null,
            "enough": enough,
            // Only a positive gap is a problem. Claiming less than the record
            // shows is not something to recalibrate away.
            "overconfident": enough && stated !== null && measured !== null && (stated - measured) > 0.1,
            "minTurns": root.minTurnsForGap,
            "minCorrections": root.minCorrectionsForGap,
            "needTurns": Math.max(0, root.minTurnsForGap - grounded.length),
            "needCorrections": Math.max(0, root.minCorrectionsForGap - corrections.length)
        };
    }

    // 36:163-182's two actions, named for what they do here rather than for a
    // proactive surface this shell does not have.
    function recalibrate() {
        root.groundingFloor = 0.85;
        root.save();
        MemoryService.remember(
            "Always say plainly when an answer is not backed by a source.",
            "instruction",
            ["asserted", `precedence:${root.precedence}`, "subject:instruction.backed"],
            root.correctionSource,
            (response, error) => {
                const tail = error && error.length > 0 ? Translation.tr(" (memory refused it: %1)").arg(error) : "";
                root.engine.addMessage(
                    Translation.tr("Recalibrated. Below 85% grounding I say I am unsure, and that is now a standing instruction in memory.") + tail,
                    root.engine.interfaceRole);
            });
    }

    function pauseRecall(days) {
        root.recallPausedUntil = Date.now() + Math.max(1, days ?? 7) * 86400000;
        root.save();
        root.engine.addMessage(
            Translation.tr("Recalled memories are paused for %1 days. Nothing was deleted; I just stop reading them into the prompt.").arg(days ?? 7),
            root.engine.interfaceRole);
    }

    function resumeRecall() {
        root.recallPausedUntil = 0;
        root.save();
    }

    /* ------------------------------------------------------------------ *
     * The hallucination bundle. Written locally, never sent (36:238).
     * ------------------------------------------------------------------ */

    property string lastReportPath: ""

    function hashOf(text) {
        let hash = 0;
        const value = String(text ?? "");
        for (let i = 0; i < value.length; i++) {
            hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0;
        }
        return (hash >>> 0).toString(16).padStart(8, "0");
    }

    function buildReport(turn, note) {
        const grounding = Grounding.computeGrounding(root.sourcesOf(turn), turn?.assistantText ?? "");
        return {
            "prompt_hash": root.hashOf(root.engine?.systemPrompt ?? ""),
            "model": root.engine?.currentModelId ?? "",
            "retrieved": root.sourcesOf(turn).map(source => ({
                "type": source.type,
                "score": source.score ?? 0,
                "redacted": true
            })),
            "grounding": grounding ? Number(grounding.value.toFixed(3)) : null,
            "note": note ?? "",
            "at": new Date().toISOString(),
            "dest": root.reportDir,
            "sent": false
        };
    }

    function saveHallucinationReport(note) {
        const turn = root.currentTurn();
        const report = root.buildReport(turn, note);
        const path = `${root.reportDir}/${Date.now()}.json`;
        reportFile.path = Qt.resolvedUrl(path);
        reportFile.setText(JSON.stringify(report, null, 2));
        root.lastReportPath = path;
        root.engine.addMessage(
            Translation.tr("Saved a local report to %1. Nothing was sent anywhere.").arg(path),
            root.engine.interfaceRole);
        return path;
    }

    readonly property FileView reportFile: FileView {}

    /* ------------------------------------------------------------------ *
     * The habit table
     * ------------------------------------------------------------------ */

    function recordProcedures(turn) {
        const calls = turn?.toolCalls ?? [];
        if (calls.length === 0) return;
        const byId = ({});
        for (const result of (turn.toolResults ?? [])) byId[result.toolCallId] = result;

        const rows = root.procedures.slice();
        let changed = false;
        for (const call of calls) {
            const name = call?.name ?? "";
            if (name.length === 0) continue;
            const pattern = root.procedureKey(name, root.callArgs(call));
            const result = byId[call.id ?? ""] ?? null;
            // A call with no result never ran: the user rejected it, or the turn
            // ended first. Neither is evidence about the tool.
            if (!result) continue;
            const outcome = root.outcomeOf(name, result.response);
            const index = rows.findIndex(row => row.tool_name === name && row.input_pattern === pattern);
            const base = index >= 0 ? rows[index] : {
                "id": rows.length + 1,
                "tool_name": name,
                "input_pattern": pattern,
                "success_count": 0,
                "failure_count": 0,
                "total_tokens_est": 0,
                "last_used": 0,
                "session_id": "",
                "approved": 0
            };
            const updated = Object.assign({}, base, {
                "success_count": base.success_count + (outcome === "success" ? 1 : 0),
                "failure_count": base.failure_count + (outcome === "failure" ? 1 : 0),
                "total_tokens_est": base.total_tokens_est + root.estimateTokens(result.response),
                "last_used": Date.now(),
                "session_id": root.engine?.sessionId ?? "",
                "approved": base.approved || ((root.engine?.approvalOf(name) ?? "never") !== "never" && outcome === "success" ? 1 : 0)
            });
            if (index >= 0) rows[index] = updated; else rows.push(updated);
            changed = true;
        }
        if (!changed) return;
        root.procedures = rows;
        root.saveProcedures();
    }

    // What a habit is worth, per :239-241: successes against everything tried.
    function actionScore(row) {
        const total = (row?.success_count ?? 0) + (row?.failure_count ?? 0);
        if (total === 0) return 0;
        return row.success_count / total;
    }

    /* ------------------------------------------------------------------ *
     * Persistence
     * ------------------------------------------------------------------ */

    function save() {
        if (!root.loaded) return;
        stateFile.setText(JSON.stringify({
            "version": 1,
            "corrections": root.corrections,
            "suppressed": root.suppressed,
            "conflicts": root.conflicts,
            "turns": root.turns,
            "recallPausedUntil": root.recallPausedUntil,
            "groundingFloor": root.groundingFloor
        }, null, 2));
    }

    function saveProcedures() {
        proceduresFile.setText(JSON.stringify({
            "version": 1,
            "table": "procedures",
            "columns": ["id", "tool_name", "input_pattern", "success_count", "failure_count",
                "total_tokens_est", "last_used", "session_id", "approved"],
            "unique": ["tool_name", "input_pattern"],
            "rows": root.procedures
        }, null, 2));
    }

    function _readJson(view) {
        try {
            const text = view.text();
            if (!text || text.trim().length === 0) return null;
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    function loadState() {
        const state = root._readJson(stateFile);
        if (state) {
            root.corrections = state.corrections ?? [];
            root.suppressed = state.suppressed ?? [];
            root.conflicts = state.conflicts ?? [];
            root.turns = state.turns ?? [];
            root.recallPausedUntil = state.recallPausedUntil ?? 0;
            root.groundingFloor = state.groundingFloor ?? 0;
        }
        const table = root._readJson(proceduresFile);
        if (table) root.procedures = table.rows ?? [];
        root.loaded = true;
    }

    // blockAllReads so a read after a write never returns the previous file,
    // the way ThreadStore learned to.
    readonly property FileView stateFile: FileView {
        path: root.statePath
        blockAllReads: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }

    readonly property FileView proceduresFile: FileView {
        path: root.proceduresPath
        blockAllReads: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }

    // FileView writes a file, not a directory tree. Nothing is read until this
    // has run, so a first install cannot lose its first correction.
    readonly property Process makeDirs: Process {
        running: true
        command: ["mkdir", "-p", root.storeDir, root.reportDir]
        onExited: root.loadState()
    }

    /* ---- windows ---- */

    property bool panelOpen: false

    function openPanel() { root.panelOpen = true; }
    function closePanel() { root.panelOpen = false; }
    function togglePanel() { root.panelOpen = !root.panelOpen; }

    // The windows themselves are loaded by the panel family, not from here. A
    // service that imports a UI package makes the two circular, and QML resolves
    // that by reporting FeedbackService as not a type at all.

    readonly property IpcHandler ipc: IpcHandler {
        target: "aifeedback"
        function open(): void { root.openPanel(); }
        function close(): void { root.closePanel(); }
        function toggle(): void { root.togglePanel(); }
        function report(): string { return JSON.stringify(root.trustReport); }
    }

}
