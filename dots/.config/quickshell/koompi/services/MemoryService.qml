pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Long-term memory for the AI assistant. Talks to the `koompi-agent-memd` Rust
 * daemon (sqlite-vec + embeddings) over newline-delimited JSON on stdin/stdout.
 *
 * The daemon is kept running for the whole session so the embedding model stays
 * loaded. Requests are correlated by an incrementing id; a sweeper times out any
 * request whose response never arrives so the chat can never hang on memory.
 *
 * Every op the daemon serves is wrapped here. Callbacks take `(response, error)`:
 * `response` is null when the call failed and `error` says why, so a refusal is
 * never reported to the model as a success.
 */
Singleton {
    id: root

    readonly property var memoryConfig: Config.options?.ai?.memory ?? ({})
    readonly property bool enabled: memoryConfig.enable ?? true
    property bool ready: false

    // For forcing initialization. QML singletons are lazy, so the daemon below
    // does not exist until something touches this service; SidebarLeft calls
    // this on first open so the model warms with the panel, not with the login.
    function load() {}
    property string provider: ""
    property int dim: 0

    readonly property string binaryPath: {
        const custom = memoryConfig.binary ?? "";
        if (custom.length > 0) return custom;
        // Derive the home directory rather than assuming /home/<user>: shipped
        // code must not hardcode where accounts live.
        return `${Directories.home}/.local/bin/koompi-agent-memd`.replace("file://", "");
    }
    readonly property string embedKey: {
        const id = memoryConfig.keyId ?? "";
        if (id.length === 0) return "";
        return KeyringStorage.keyringData?.apiKeys?.[id]?.key ?? "";
    }

    /* ---- the type vocabulary the daemon enforces (memd src/taxonomy.rs) ---- */

    readonly property var memoryTypes: ["identity", "contact", "preference", "instruction", "project", "task", "fact", "episodic"]
    readonly property var typeAliases: ({ "profile": "identity" })
    // The daemon's eight types onto the three groups the memory spec names.
    // `episodic` is the pre-extraction consolidator's stamp and has no spec
    // group: it is transcript, and the browser says so rather than hiding it.
    readonly property var typeGroups: ({
        "identity": "USER",
        "contact": "USER",
        "fact": "USER",
        "project": "PROJECT",
        "task": "PROJECT",
        "preference": "FEEDBACK",
        "instruction": "FEEDBACK",
        "episodic": "IMPORTED TRANSCRIPT"
    })
    readonly property var groupOrder: ["USER", "PROJECT", "FEEDBACK", "IMPORTED TRANSCRIPT"]

    function canonicalType(type) {
        const t = (type ?? "").trim().toLowerCase();
        const aliased = root.typeAliases[t] ?? t;
        return root.memoryTypes.indexOf(aliased) >= 0 ? aliased : "";
    }

    function groupOf(type) {
        return root.typeGroups[root.canonicalType(type)] ?? "IMPORTED TRANSCRIPT";
    }

    /* ---- request plumbing ---- */

    property int nextId: 1
    property var pending: ({}) // id -> { callback, deadline, op }
    // `pending` is a plain object, so mutating it emits no change signal. This
    // counter is what the timeout sweeper below can actually bind to.
    property int pendingCount: 0
    readonly property int timeoutMs: 4000
    // A recall rides the priority lane and answers in milliseconds; consolidate
    // rides the bulk lane and embeds every statement it extracts. One deadline
    // for both either cut off the second or left the chat waiting on the first.
    readonly property var opTimeouts: ({
        "ping": 2000,
        "stats": 2000,
        "recall": 3000,
        "forget": 2000,
        "reinforce": 2000,
        "append_event": 2000,
        "list": 5000,
        "list_events": 5000,
        "remember": 8000,
        "decay": 20000,
        "prune": 20000,
        "consolidate": 60000
    })

    // Turns written before the daemon finished loading its embedding model used
    // to be dropped, which cost the opening turns of every session - the ones
    // where a person says who they are.
    property var _queue: []
    readonly property int maxQueued: 500
    readonly property var queueableOps: ["append_event"]

    property string lastError: ""

    function _send(obj, callback) {
        if (!root.enabled) {
            if (callback) callback(null, "memory is disabled");
            return;
        }
        if (!root.ready) {
            if (root.queueableOps.indexOf(obj.op) >= 0) {
                if (root._queue.length < root.maxQueued) root._queue.push(obj);
                return;
            }
            if (callback) callback(null, "the memory daemon is not ready yet");
            return;
        }
        const id = root.nextId++;
        obj.id = id;
        root.pending[id] = {
            "callback": callback,
            "deadline": Date.now() + (root.opTimeouts[obj.op] ?? root.timeoutMs),
            "op": obj.op
        };
        root.pendingCount++;
        daemon.write(JSON.stringify(obj) + "\n");
    }

    function _flushQueue() {
        const queued = root._queue;
        root._queue = [];
        for (let i = 0; i < queued.length; i++) root._send(queued[i], null);
        if (queued.length > 0) console.log(`[MemoryService] flushed ${queued.length} queued event(s)`);
    }

    /* ---- the daemon's ops, one function each ---- */

    function appendEvent(sessionId, actor, content, tags) {
        if (!content || content.trim().length === 0) return;
        root._send({
            "op": "append_event",
            "session_id": sessionId ?? "default",
            "actor": actor ?? "assistant",
            "content": content,
            "tags": tags ?? []
        }, null);
        // The assistant's turn is the only evidence the shell has that a recalled
        // memory was actually used, so Hebbian reinforcement hangs off it.
        if ((actor ?? "assistant") === "assistant") root._reinforceUsed(content);
    }

    // Store a durable memory. Type must be one of `memoryTypes`; the daemon
    // rejects anything else, and so does this, with the same message.
    function remember(text, type, tags, source, callback) {
        const mtype = root.canonicalType(type ?? "fact");
        if (mtype.length === 0) {
            const error = `unknown memory type '${type}'; valid types are ${root.memoryTypes.join(", ")}`;
            root.lastError = error;
            if (callback) callback(null, error);
            return;
        }
        root._send({
            "op": "remember",
            "text": text,
            "mtype": mtype,
            "tags": tags ?? [],
            "source": source ?? "chat"
        }, callback);
    }

    // Retrieve the top-k relevant memories. callback receives (results, error);
    // `results` is an array (possibly empty) or null when the call failed.
    //
    // `purpose` defaults to "turn": the recall that feeds the model. Only those
    // update `lastRecall`, so the browser's own searches never masquerade as
    // what the assistant was given.
    function recall(query, k, callback, purpose) {
        root._send({
            "op": "recall",
            "query": query,
            "k": k ?? (root.memoryConfig.recallCount ?? 4)
        }, (response, error) => {
            const results = response?.results ?? null;
            if (results && (purpose ?? "turn") === "turn") {
                root.lastRecallQuery = query;
                root.lastRecallUsed = [];
                root.lastRecallAt = Date.now();
                root.lastRecall = results;
                root.recalled(query, results);
            }
            if (callback) callback(results, error);
        });
    }

    function forget(memoryId, callback) {
        root._send({ "op": "forget", "memory_id": memoryId }, callback);
    }

    function list(limit, callback, offset) {
        root._send({ "op": "list", "limit": limit ?? 50, "offset": offset ?? 0 }, callback);
    }

    function reinforce(memoryId, callback) {
        root._send({ "op": "reinforce", "memory_id": memoryId }, callback);
    }

    function decay(callback) {
        root._send({ "op": "decay" }, callback);
    }

    function stats(callback) {
        root._send({ "op": "stats" }, callback);
    }

    function listEvents(since, consolidated, callback) {
        root._send({
            "op": "list_events",
            "since": since ?? 0,
            "consolidated": consolidated ?? null
        }, callback);
    }

    // The daemon schedules its own passes (T0 at 45 s of quiet, T1 at 300 s).
    // This is the browser's "consolidate now", nothing else.
    function consolidate(limit, callback) {
        root._send({ "op": "consolidate", "limit": limit ?? 40 }, callback);
    }

    // dry_run defaults to true daemon-side; it is spelled out here because the
    // false case archives rows.
    function prune(dryRun, callback) {
        root._send({ "op": "prune", "dry_run": dryRun !== false }, callback);
    }

    function ping(callback) {
        root._send({ "op": "ping" }, callback);
    }

    // memd has no update op: a memory's text is what its embedding was built
    // from, so an edit is a delete and a fresh write. The id, strength and
    // access count do not survive it, and the browser says so before it runs.
    function edit(memoryId, text, type, tags, source, callback) {
        root.remember(text, type, tags, source, (response, error) => {
            if (!response) {
                if (callback) callback(null, error);
                return;
            }
            root.forget(memoryId, () => {
                if (callback) callback(response, "");
            });
        });
    }

    // No clear-all op either; this is `forget` over everything `list` returns.
    function clearAll(callback) {
        root.list(1000, (response, error) => {
            const rows = response?.results ?? null;
            if (!rows) {
                if (callback) callback(null, error);
                return;
            }
            let left = rows.length;
            if (left === 0) {
                if (callback) callback(0, "");
                return;
            }
            let forgotten = 0;
            for (let i = 0; i < rows.length; i++) {
                root.forget(rows[i].id, response2 => {
                    if (response2) forgotten++;
                    left--;
                    if (left === 0 && callback) callback(forgotten, "");
                });
            }
        });
    }

    /* ---- what the last turn was given, and what it used ---- */

    // The memories injected into the current turn's prompt, with the daemon's
    // own scores. Published, not rendered: J06 draws it beside the answer.
    property var lastRecall: []
    property string lastRecallQuery: ""
    property double lastRecallAt: 0
    // Subset of `lastRecall` the answer demonstrably used, and so reinforced.
    property var lastRecallUsed: []
    signal recalled(string query, var results)

    // The shell-wide source row shape: {type, name, detail, score, url}.
    readonly property var recallSources: root.lastRecall.map(memory => {
        const used = root.lastRecallUsed.indexOf(memory.id) >= 0;
        const strength = (memory.strength ?? 0).toFixed(2);
        return {
            "type": "memory",
            "name": memory.text.length > 80 ? `${memory.text.substring(0, 79)}…` : memory.text,
            "detail": `${memory.mtype ?? "fact"} · strength ${strength}${used ? " · used in this answer" : ""}`,
            "score": memory.score ?? 0,
            "url": ""
        };
    })

    // Append, never clobber: J02 owns the web, file and agent rows on the same list.
    function withMemorySources(existing) {
        const rows = Array.isArray(existing) ? existing.slice() : [];
        return rows.concat(root.recallSources);
    }

    readonly property var _stopWords: ["that", "this", "with", "from", "they", "them", "have", "been", "their", "about", "when", "what", "which", "would", "there", "into", "your", "yours", "also", "than", "then", "some", "more", "very", "just", "user", "will", "does", "like", "want", "wants"]

    function _fedTheAnswer(memoryText, answer) {
        const words = (memoryText ?? "").toLowerCase().match(/[a-z0-9]{4,}/g) ?? [];
        const keys = [];
        for (let i = 0; i < words.length; i++) {
            if (root._stopWords.indexOf(words[i]) < 0 && keys.indexOf(words[i]) < 0) keys.push(words[i]);
        }
        if (keys.length === 0) return false;
        const haystack = (answer ?? "").toLowerCase();
        let hits = 0;
        for (let i = 0; i < keys.length; i++) if (haystack.indexOf(keys[i]) >= 0) hits++;
        const needed = keys.length === 1 ? 1 : Math.max(2, Math.ceil(keys.length * 0.5));
        return hits >= needed;
    }

    function _reinforceUsed(answer) {
        if (root.lastRecall.length === 0) return;
        // A recall belongs to the turn it was made for. Five minutes later it is
        // some other conversation's context and reinforcing it is a lie.
        if (Date.now() - root.lastRecallAt > 300000) return;
        const used = [];
        for (let i = 0; i < root.lastRecall.length; i++) {
            const memory = root.lastRecall[i];
            if (!root._fedTheAnswer(memory.text, answer)) continue;
            used.push(memory.id);
            root.reinforce(memory.id, null);
        }
        root.lastRecallUsed = used;
        if (used.length > 0) console.log(`[MemoryService] reinforced ${used.length} recalled memor(ies): ${used.join(", ")}`);
    }

    /* ---- the browser ---- */

    property bool browserOpen: false

    function openBrowser() { root.browserOpen = true; }
    function closeBrowser() { root.browserOpen = false; }
    function toggleBrowser() { root.browserOpen = !root.browserOpen; }

    // Loaded by the panel family. A service that imports a UI package makes the
    // two circular, and QML reports the service as not being a type.

    IpcHandler {
        target: "memory"
        function open(): void { root.openBrowser(); }
        function close(): void { root.closeBrowser(); }
        function toggle(): void { root.toggleBrowser(); }
    }

    /* ---- process ---- */

    // Quickshell doesn't auto-restart an exited Process, so we do it ourselves
    // with a bounded number of attempts to avoid a hot crash loop.
    property int restartAttempts: 0
    readonly property int maxRestarts: 5

    function _handleLine(line) {
        if (line.trim().length === 0) return;
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            console.error("[MemoryService] bad response line:", line);
            return;
        }
        const entry = root.pending[msg.id];
        if (!entry) {
            // The startup banner is the line carrying the daemon's version, not
            // every line with id 0: anything else unsolicited must not be able
            // to masquerade as it.
            if (msg.version !== undefined) {
                root.ready = true;
                root.restartAttempts = 0;
                root.provider = msg.provider ?? "";
                root.dim = msg.dim ?? 0;
                console.log(`[MemoryService] ready: provider=${root.provider} dim=${root.dim}`);
                root._flushQueue();
            } else {
                console.log("[MemoryService] unsolicited line:", line);
            }
            return;
        }
        delete root.pending[msg.id];
        root.pendingCount--;
        const error = msg.ok ? "" : (msg.error ?? "the memory daemon refused the request");
        if (!msg.ok) {
            root.lastError = error;
            console.error(`[MemoryService] ${entry.op} refused: ${error}`);
        }
        if (entry.callback) entry.callback(msg.ok ? msg : null, error);
    }

    Process {
        id: daemon
        // Waits for the config: launching before it parses started the daemon on
        // the default path and ignored `ai.memory.binary` for the whole session,
        // because a Process does not relaunch when its command changes.
        running: root.enabled && Config.ready
        command: [root.binaryPath]
        environment: ({
            "KOOMPI_AGENT_EMBED_PROVIDER": root.memoryConfig.provider ?? "local",
            "KOOMPI_AGENT_EMBED_KEY": root.embedKey
        })
        stdinEnabled: true

        stdout: SplitParser {
            onRead: data => root._handleLine(data)
        }
        stderr: SplitParser {
            onRead: data => console.error("[MemoryService:memd]", data)
        }
        onExited: (code, status) => {
            root.ready = false;
            // Fail every in-flight request so callers don't hang.
            for (const id in root.pending) {
                const entry = root.pending[id];
                if (entry.callback) entry.callback(null, "the memory daemon exited");
            }
            root.pending = ({});
            root.pendingCount = 0;
            if (root.enabled && root.restartAttempts < root.maxRestarts) {
                console.error(`[MemoryService] daemon exited (code ${code}); restarting (attempt ${root.restartAttempts + 1}/${root.maxRestarts}).`);
                restartTimer.start();
            } else {
                console.error(`[MemoryService] daemon exited (code ${code}); giving up after ${root.restartAttempts} attempts.`);
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 2000
        onTriggered: {
            root.restartAttempts++;
            daemon.running = true;
        }
    }

    // Times out requests whose response never arrives, so callers always settle.
    // Only runs while something is in flight: sweeping an empty map once a
    // second was the shell's single busiest unconditional timer.
    Timer {
        interval: 1000
        repeat: true
        running: root.enabled && root.pendingCount > 0
        onTriggered: {
            const now = Date.now();
            for (const id in root.pending) {
                const entry = root.pending[id];
                if (now > entry.deadline) {
                    delete root.pending[id];
                    root.pendingCount--;
                    if (entry.callback) entry.callback(null, `${entry.op} timed out after ${root.opTimeouts[entry.op] ?? root.timeoutMs} ms`);
                }
            }
        }
    }
}
