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
 */
Singleton {
    id: root

    readonly property var memoryConfig: Config.options?.ai?.memory ?? ({})
    readonly property bool enabled: memoryConfig.enable ?? true
    property bool ready: false
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

    property int nextId: 1
    property var pending: ({}) // id -> { callback, deadline }
    readonly property int timeoutMs: 4000

    // Episodic event log wiring (#7)
    property int _eventCount: 0

    function appendEvent(sessionId, actor, content, tags) {
        if (!root.enabled || !root.ready || !content || content.trim().length === 0) return;
        root._send({
            "op": "append_event",
            "session_id": sessionId ?? "default",
            "actor": actor ?? "assistant",
            "content": content,
            "tags": tags ?? []
        }, null);
        root._eventCount++;
        if (root._eventCount % 20 === 0) {
            root._send({ "op": "decay" }, null);
            root._send({ "op": "consolidate", "limit": 40 }, null);
        }
    }

    function consolidate(limit, callback) {
        root._send({ "op": "consolidate", "limit": limit ?? 40 }, callback);
    }

    // Quickshell doesn't auto-restart an exited Process, so we do it ourselves
    // with a bounded number of attempts to avoid a hot crash loop.
    property int restartAttempts: 0
    readonly property int maxRestarts: 5

    function _send(obj, callback) {
        if (!root.enabled || !root.ready) {
            if (callback) callback(null);
            return;
        }
        const id = root.nextId++;
        obj.id = id;
        root.pending[id] = {
            "callback": callback,
            "deadline": Date.now() + root.timeoutMs
        };
        daemon.write(JSON.stringify(obj) + "\n");
    }

    // Store a durable memory. type: profile | preference | fact | task
    function remember(text, type, tags, source, callback) {
        root._send({
            "op": "remember",
            "text": text,
            "mtype": type ?? "fact",
            "tags": tags ?? [],
            "source": source ?? "chat"
        }, callback);
    }

    // Retrieve the top-k relevant memories. callback receives an array (possibly
    // empty) or null on timeout / disabled.
    function recall(query, k, callback) {
        if (!root.enabled || !root.ready) {
            if (callback) callback(null);
            return;
        }
        root._send({
            "op": "recall",
            "query": query,
            "k": k ?? (root.memoryConfig.recallCount ?? 4)
        }, response => {
            callback(response?.results ?? null);
        });
    }

    function forget(memoryId, callback) {
        root._send({ "op": "forget", "memory_id": memoryId }, callback);
    }

    function list(limit, callback) {
        root._send({ "op": "list", "limit": limit ?? 50 }, callback);
    }

    function _handleLine(line) {
        if (line.trim().length === 0) return;
        let msg;
        try {
            msg = JSON.parse(line);
        } catch (e) {
            console.error("[MemoryService] bad response line:", line);
            return;
        }
        // id 0 is the unsolicited ready/ping banner emitted on startup.
        if (msg.id === 0) {
            root.ready = true;
            root.restartAttempts = 0;
            root.provider = msg.provider ?? "";
            root.dim = msg.dim ?? 0;
            console.log(`[MemoryService] ready: provider=${root.provider} dim=${root.dim}`);
            return;
        }
        const entry = root.pending[msg.id];
        if (!entry) return;
        delete root.pending[msg.id];
        if (entry.callback) entry.callback(msg.ok ? msg : null);
    }

    Process {
        id: daemon
        running: root.enabled
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
                if (entry.callback) entry.callback(null);
            }
            root.pending = ({});
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
    Timer {
        interval: 1000
        repeat: true
        running: root.enabled
        onTriggered: {
            const now = Date.now();
            for (const id in root.pending) {
                const entry = root.pending[id];
                if (now > entry.deadline) {
                    delete root.pending[id];
                    if (entry.callback) entry.callback(null);
                }
            }
        }
    }
}
