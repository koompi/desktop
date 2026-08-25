.pragma library
.import "feedbackRules.js" as Rules

// What the correction loop writes and measures, on top of the rules in
// feedbackRules.js: the record a correction is stored as, the turn read off
// the conversation, the suppression keys, and the habit table's keying and
// outcome rules. Still no QML type: tests/test_ai_correction.sh imports this
// into node next to the rules. FeedbackService.qml imports it as `Writes`.

/* ---- what a correction is written as ---- */

function tagsFor(record) {
    const tags = ["asserted", `precedence:${Rules.precedence}`];
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
        "precedence": Rules.precedence,
        "source": Rules.correctionSource,
        "tags": tagsFor(record),
        "durable": (record?.scope ?? "durable") !== "once"
    };
}

// Types a typed correction without asking the user to pick one.
function draftFrom(text, claim) {
    const value = String(text ?? "").trim();
    if (value.length === 0) return null;
    const fromRules = Rules.correctionFrom(value);
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
    const statement = Rules.asStatement(value);
    const subject = Rules.subjectOf(statement);
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
    return `${type}|${Rules.normalise(identity)}`;
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

function hashOf(text) {
    let hash = 0;
    const value = String(text ?? "");
    for (let i = 0; i < value.length; i++) {
        hash = ((hash << 5) - hash + value.charCodeAt(i)) | 0;
    }
    return (hash >>> 0).toString(16).padStart(8, "0");
}
