.pragma library

// The pure rules of the correction loop. No QML type is reachable from here on
// purpose: the same functions are imported into node by
// tests/test_ai_correction.sh and run against the observed transcript.
// FeedbackService.qml imports this as `Rules` and calls through.

// Precedence has no column in memd, so it rides the tags and the source stamp
// that memd does store. FeedbackService re-exports both.
var precedence = "asserted";
var correctionSource = "manual-correction";

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
    const words = contentWords(text);
    return words.length > 0 ? words[0] : "";
}

function overlaps(a, b) {
    const left = contentWords(a);
    const right = contentWords(b);
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
    const left = normalise(a);
    const right = normalise(b);
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
    for (const clause of clausesOf(text)) {
        if (/^(?:and\s+|but\s+|so\s+|no,?\s+|actually,?\s+)?(?:you|your)\b/i.test(clause)) continue;
        const match = /^(?:and\s+|but\s+|so\s+|no,?\s+|actually,?\s+|hey,?\s+)?(?:i['’]m|im|i\s+am|my\s+name\s+is|my\s+name['’]s|call\s+me|i\s+go\s+by)\b\s+(.+)$/i.exec(clause);
        if (!match) continue;
        let rest = match[1].trim();
        if (/^(?:not|never)\b/i.test(rest)) continue;
        rest = rest.replace(/^(?:actually|really|still)\s+/i, "");
        const name = nameToken(rest);
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
    return /[.!?]$/.test(value) ? capitalise(value) : capitalise(value) + ".";
}

// What the user's own turn asserts, if anything. Precision over recall, the
// same trade memd's extractor makes: a rule that is not certain returns null
// and the turn is left alone.
function correctionFrom(userText) {
    const name = ownerNameFrom(userText);
    if (name.length > 0) {
        return {
            "kind": "owner-name",
            "value": name,
            "statement": `The user's name is ${name}.`,
            "mtype": "identity",
            "subject": "owner.name"
        };
    }
    for (const clause of clausesOf(userText)) {
        let match = /^(?:and\s+|but\s+|so\s+)?from\s+now\s+on,?\s+(.+)$/i.exec(clause);
        if (match) {
            const body = match[1].trim();
            return {
                "kind": "instruction",
                "value": body,
                "statement": asStatement(`From now on ${body}`),
                "mtype": "instruction",
                "subject": `instruction.${keyWord(body)}`
            };
        }
        match = /^(?:and\s+|but\s+|so\s+)?(always|never)\s+(.+)$/i.exec(clause);
        if (match) {
            const body = `${match[1].toLowerCase()} ${match[2].trim()}`;
            return {
                "kind": "instruction",
                "value": body,
                "statement": asStatement(body),
                "mtype": "instruction",
                "subject": `instruction.${keyWord(match[2])}`
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
                "subject": `user.prefers.${keyWord(body)}`
            };
        }
        match = /^(?:and\s+|but\s+|so\s+)?remember\s+that\s+(.+)$/i.exec(clause);
        if (match) {
            const body = match[1].trim();
            return {
                "kind": "fact",
                "value": body,
                "statement": asStatement(body),
                "mtype": "fact",
                "subject": subjectOf(asStatement(body)).subject
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
        const args = callArgs(call);
        if (correction.kind === "owner-name") {
            if (name !== "set_owner_name") continue;
            if (sameValue(args.name, correction.value)) return call;
            continue;
        }
        if (name !== "remember") continue;
        if (overlaps(args.text ?? "", correction.statement)) return call;
    }
    return null;
}

function auditTurn(turn) {
    const calls = turn?.toolCalls ?? [];
    const correction = correctionFrom(turn?.userText ?? "");
    const claimed = claimsStorage(turn?.assistantText ?? "");
    if (!correction) {
        return {
            "verdict": (claimed && storageCalls(calls).length === 0) ? "claim-without-call" : "none",
            "claimed": claimed,
            "correction": null,
            "backing": null
        };
    }
    const backing = backingCall(calls, correction);
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
    if (match) return { "subject": `user.prefers.${keyWord(match[1])}`, "value": match[1].trim() };
    match = /^(?:always|never|from\s+now\s+on)\s+(.+)$/.exec(text);
    if (match) return { "subject": `instruction.${keyWord(match[1])}`, "value": text };
    return { "subject": "", "value": text };
}

function contradicts(assertedSubject, assertedValue, statement) {
    const incoming = subjectOf(statement);
    if (incoming.subject.length === 0) return false;
    if (incoming.subject !== assertedSubject) return false;
    return !sameValue(incoming.value, assertedValue);
}

/* ---- what a turn is ---- */

// Everything since the last thing the user typed: what they said, what the
// assistant said back, every call it made and every result it got. Read off
// the conversation's message list; it is the record every rule below judges.
function turnFrom(conversation) {
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

/* ---- suppression: a source is keyed, and a row is matched to a key ---- */

function sourceKey(source) {
    const type = String(source?.type ?? "memory");
    const identity = String(source?.url ?? "").length > 0 ? source.url : String(source?.name ?? "");
    return `${type}|${normalise(identity)}`;
}

// `suppressed` is the store's list; a row loses on its id when the entry has
// one, and on its leading text otherwise.
function isMemorySuppressed(row, suppressed) {
    const text = String(row?.text ?? "");
    for (const entry of suppressed) {
        if (!entry.active || entry.type !== "memory") continue;
        if (entry.memoryId >= 0 && entry.memoryId === row?.id) return true;
        const name = String(entry.name ?? "").replace(/…$/, "");
        if (name.length > 0 && text.indexOf(name) === 0) return true;
    }
    return false;
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

/* ---- what a correction is written as ---- */

function tagsFor(record) {
    const tags = ["asserted", `precedence:${precedence}`];
    const subject = record?.subject ?? "";
    if (subject.length > 0) tags.push(`subject:${subject}`);
    return tags;
}

// What the modal shows before it writes anything. Same object the write uses.
// `store` is the translated label of the memory store; translation is QML's.
function provenanceOf(record, store) {
    return {
        "store": store,
        "statement": record?.statement ?? "",
        "mtype": record?.mtype ?? "fact",
        "precedence": precedence,
        "source": correctionSource,
        "tags": tagsFor(record),
        "durable": (record?.scope ?? "durable") !== "once"
    };
}

// Types a typed correction without asking the user to pick one.
function draftFrom(text, claim) {
    const value = String(text ?? "").trim();
    if (value.length === 0) return null;
    const fromRules = correctionFrom(value);
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
    const statement = asStatement(value);
    const subject = subjectOf(statement);
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

function hashOf(text) {
    let hash = 0;
    const value = String(text ?? "");
    for (let i = 0; i < value.length; i++) {
        hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0;
    }
    return (hash >>> 0).toString(16).padStart(8, "0");
}
