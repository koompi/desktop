pragma ComponentBehavior: Bound

import qs.modules.common
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Every conversation on disk. One JSON file per thread under
 * `Directories.aiChats`, plus `index.json` carrying title, session id and
 * timestamps. The index is a cache — a directory scan rebuilds it from the
 * files whenever it is missing or disagrees with them, so losing it costs a
 * title, never a conversation.
 */
QtObject {
    id: root

    property bool active: true
    property string directory: Directories.aiChats

    readonly property string indexName: "index"
    readonly property string autosaveAlias: "lastSession"
    readonly property int titleLength: 48

    property var threads: []
    property string currentThreadId: ""
    property bool loaded: false

    signal refreshed()

    readonly property var currentThread: root.threadFor(root.currentThreadId)
    readonly property string sessionId: root.currentThread ? (root.currentThread.sessionId ?? "") : ""
    readonly property string currentTitle: root.currentThread ? (root.currentThread.title ?? "") : ""

    function threadFor(id) {
        if (!id) return null;
        const list = root.threads;
        for (let i = 0; i < list.length; i++)
            if (list[i].id === id) return list[i];
        return null;
    }

    function pathFor(id) {
        return `${root.directory}/${id}.json`;
    }

    function newSessionId() {
        return Math.random().toString(36).slice(2, 8);
    }

    function newThreadId() {
        return "t" + Date.now().toString(36) + Math.random().toString(36).slice(2, 6);
    }

    function titleFrom(text) {
        const flat = (text ?? "")
            .replace(/```[\s\S]*?```/g, " ")
            .replace(/[#*_`>\[\]]/g, " ")
            .replace(/\s+/g, " ")
            .trim();
        if (flat.length === 0) return "";
        if (flat.length <= root.titleLength) return flat;
        const cut = flat.slice(0, root.titleLength);
        const space = cut.lastIndexOf(" ");
        return (space > root.titleLength / 2 ? cut.slice(0, space) : cut) + "…";
    }

    // --- disk -----------------------------------------------------------

    // blockAllReads, not blockLoading: blockLoading only blocks the very first
    // load, so after `path` changes `text()` returns the *previous* file's
    // content instead of waiting. That silent stale read is how a save followed
    // by a load emptied a conversation.
    readonly property FileView threadFile: FileView {
        path: ""
        blockAllReads: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }

    readonly property FileView indexFile: FileView {
        path: root.active ? `${root.directory}/${root.indexName}.json` : ""
        blockAllReads: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }

    function _readJson(view, path) {
        try {
            if (view.path === path) view.reload();
            else view.path = path;
            const text = view.text();
            if (!text || text.trim().length === 0) return null;
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    /**
     * @returns {messages, meta} or null. Never throws, never returns a partial
     * read — the caller may only replace a live conversation on a non-null.
     */
    function readThread(id) {
        const data = root._readJson(root.threadFile, root.pathFor(id));
        if (data === null) return null;
        if (Array.isArray(data)) return { "messages": data, "meta": {} };
        if (Array.isArray(data.messages)) {
            const meta = Object.assign({}, data);
            delete meta.messages;
            return { "messages": data.messages, "meta": meta };
        }
        return null;
    }

    function writeThread(id, messages, meta) {
        const record = root.threadFor(id);
        const payload = {
            "version": 2,
            "id": id,
            "title": (meta && meta.title) || (record ? record.title : "") || "",
            "sessionId": (meta && meta.sessionId) || (record ? record.sessionId : "") || "",
            "createdAt": (record ? record.createdAt : 0) || Date.now(),
            "updatedAt": Date.now(),
            "messages": messages,
        };
        root.threadFile.path = root.pathFor(id);
        root.threadFile.setText(JSON.stringify(payload));
        return payload;
    }

    function writeIndex() {
        if (!root.active) return;
        root.indexFile.setText(JSON.stringify({ "version": 1, "threads": root.threads }));
    }

    // --- listing --------------------------------------------------------

    readonly property Process scanner: Process {
        property var names: []
        stdout: SplitParser {
            onRead: line => { if (line.length > 0) scanner.names.push(line); }
        }
        onExited: {
            const names = scanner.names;
            scanner.names = [];
            root._reconcile(names);
            root.loaded = true;
            root.refreshed();
        }
    }

    readonly property Process remover: Process {}

    function refresh() {
        if (!root.active) return;
        if (root.scanner.running) return;
        root.scanner.names = [];
        root.scanner.command = ["sh", "-c",
            `mkdir -p "$1" && ls -1 "$1" 2>/dev/null | sed -n 's/\\.json$//p'`, "sh", root.directory];
        root.scanner.running = true;
    }

    function _reconcile(names) {
        const onDisk = names.filter(n => n !== root.indexName && n.length > 0);
        const stored = root._readJson(root.indexFile, root.indexFile.path);
        const known = (stored && Array.isArray(stored.threads)) ? stored.threads : [];

        const byId = ({});
        root.threads.forEach(t => { if (t && t.id) byId[t.id] = t; });
        known.forEach(t => { if (t && t.id) byId[t.id] = t; });

        // The active thread stays listed even before its first save lands.
        const ids = onDisk.slice();
        if (root.currentThreadId.length > 0 && ids.indexOf(root.currentThreadId) < 0)
            ids.push(root.currentThreadId);

        const kept = ids.map(id => byId[id] ?? root._adopt(id));
        kept.sort((a, b) => (b.updatedAt ?? 0) - (a.updatedAt ?? 0));
        root.threads = kept;

        const before = known.map(t => t.id).sort().join(",");
        const after = kept.map(t => t.id).sort().join(",");
        if (before !== after) root.writeIndex();
    }

    /**
     * A thread file with no index entry. Its own metadata wins where it has
     * any; a legacy file (a bare message array) gets a title read off its first
     * user message and a fresh session id. Nothing on disk is rewritten here.
     */
    function _adopt(id) {
        const data = root.readThread(id);
        const meta = data ? data.meta : {};
        const messages = data ? data.messages : [];
        let title = meta.title ?? "";
        if (title.length === 0) {
            const first = messages.find(m => m && m.role === "user" && (m.rawContent ?? "").length > 0);
            title = first ? root.titleFrom(first.rawContent) : "";
        }
        if (title.length === 0) title = id === root.autosaveAlias ? "Previous conversation" : id;
        return {
            "id": id,
            "title": title,
            "sessionId": meta.sessionId ?? root.newSessionId(),
            "createdAt": meta.createdAt ?? (messages.length > 0 ? (messages[0].timestamp ?? Date.now()) : Date.now()),
            "updatedAt": meta.updatedAt ?? (messages.length > 0 ? (messages[messages.length - 1].timestamp ?? Date.now()) : Date.now()),
            "messageCount": messages.length,
            "titleLocked": false,
        };
    }

    // --- mutation -------------------------------------------------------

    function createThread(title) {
        const id = root.newThreadId();
        const now = Date.now();
        root.threads = [{
            "id": id,
            "title": title ?? "",
            "sessionId": root.newSessionId(),
            "createdAt": now,
            "updatedAt": now,
            "messageCount": 0,
            "titleLocked": (title ?? "").length > 0,
        }, ...root.threads];
        root.currentThreadId = id;
        root.writeThread(id, [], null);
        root.writeIndex();
        return id;
    }

    /** The thread saves land in, created on demand so a save can never go nowhere. */
    function ensureCurrentThread() {
        if (root.threadFor(root.currentThreadId)) return root.currentThreadId;
        if (root.currentThreadId.length > 0) {
            root._register(root.currentThreadId);
            return root.currentThreadId;
        }
        return root.createThread("");
    }

    function _register(id) {
        if (root.threadFor(id)) return;
        const now = Date.now();
        root.threads = [{
            "id": id,
            "title": "",
            "sessionId": root.newSessionId(),
            "createdAt": now,
            "updatedAt": now,
            "messageCount": 0,
            "titleLocked": false,
        }, ...root.threads];
    }

    function selectThread(id) {
        root._register(id);
        root.currentThreadId = id;
    }

    function renameThread(id, title) {
        const clean = (title ?? "").trim();
        if (clean.length === 0) return false;
        return root._patch(id, { "title": clean, "titleLocked": true });
    }

    /** The title the user never types: first exchange in, one line out. */
    function suggestTitle(id, text) {
        const record = root.threadFor(id);
        if (!record || record.titleLocked || (record.title ?? "").length > 0) return false;
        const title = root.titleFrom(text);
        if (title.length === 0) return false;
        return root._patch(id, { "title": title });
    }

    function noteSaved(id, messageCount) {
        return root._patch(id, { "messageCount": messageCount, "updatedAt": Date.now() });
    }

    function noteLoaded(id, messageCount) {
        return root._patch(id, { "messageCount": messageCount });
    }

    /** Metadata a thread file carries about itself outranks a rebuilt guess. */
    function adoptMeta(id, meta) {
        if (!meta) return false;
        const fields = ({});
        if (meta.sessionId) fields.sessionId = meta.sessionId;
        if (meta.createdAt) fields.createdAt = meta.createdAt;
        const record = root.threadFor(id);
        if (meta.title && record && (record.title ?? "").length === 0) fields.title = meta.title;
        if (Object.keys(fields).length === 0) return false;
        return root._patch(id, fields);
    }

    function _patch(id, fields) {
        const list = root.threads.slice();
        const i = list.findIndex(t => t.id === id);
        if (i < 0) return false;
        list[i] = Object.assign({}, list[i], fields);
        root.threads = list;
        root.writeIndex();
        return true;
    }

    function deleteThread(id) {
        const list = root.threads.filter(t => t.id !== id);
        if (list.length === root.threads.length) return false;
        root.threads = list;
        if (root.currentThreadId === id) root.currentThreadId = "";
        root.writeIndex();
        root.remover.command = ["rm", "-f", root.pathFor(id)];
        root.remover.running = true;
        return true;
    }

    Component.onCompleted: if (root.active) root.refresh()
}
