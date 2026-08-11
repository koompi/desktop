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
    property bool indexLoaded: false

    // Which thread was open when the shell last ran. `lastSession` is an alias
    // for "the active thread", so a restart has to be able to resolve it to one.
    property string lastActiveId: ""

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
        root.ensureIndexLoaded();
        const record = root.threadFor(id);
        const payload = {
            "version": 2,
            "id": id,
            "title": (meta && meta.title) || (record ? record.title : "") || "",
            // Carried in the file as well as the index, so a lost index costs a
            // generated title and never a typed one.
            "titleLocked": Boolean(record && record.titleLocked),
            "sessionId": (meta && meta.sessionId) || (record ? record.sessionId : "") || "",
            "createdAt": (record ? record.createdAt : 0) || Date.now(),
            "updatedAt": Date.now(),
            "messages": messages,
        };
        root.threadFile.path = root.pathFor(id);
        root.threadFile.setText(JSON.stringify(payload));
        return payload;
    }

    /**
     * The index, read synchronously the first time anything touches the store.
     *
     * The directory scan is a Process, so it answers a turn of the event loop
     * later — and the shell restores `lastSession` before that. Reading the
     * index only inside the scan callback meant every startup ran its first
     * save against an empty thread list and wrote that emptiness over the file,
     * which is how a hand-typed title disappeared on restart. The scan finds
     * files the index does not know about; it is not how the index is read.
     */
    function ensureIndexLoaded() {
        if (root.indexLoaded || !root.active) return;
        root.indexLoaded = true;
        const stored = root._readJson(root.indexFile, root.indexFile.path);
        const known = (stored && Array.isArray(stored.threads)) ? stored.threads : [];
        if (known.length > 0) root.threads = known;
        if (stored && stored.current) root.lastActiveId = stored.current;
    }

    function writeIndex() {
        if (!root.active) return;
        // Never write a list built before the stored one was read.
        if (!root.indexLoaded) return;
        root.indexFile.setText(JSON.stringify({
            "version": 1,
            "current": root.currentThreadId || root.lastActiveId,
            "threads": root.threads,
        }));
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
        root.ensureIndexLoaded();
        const onDisk = names.filter(n => n !== root.indexName && n.length > 0);
        const stored = root._readJson(root.indexFile, root.indexFile.path);
        const known = (stored && Array.isArray(stored.threads)) ? stored.threads : [];

        // Memory wins: it already holds the index plus everything that happened
        // while the scan was in flight. The file is only consulted for records
        // this instance never loaded.
        const byId = ({});
        known.forEach(t => { if (t && t.id) byId[t.id] = t; });
        root.threads.forEach(t => { if (t && t.id) byId[t.id] = t; });

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
        let title = meta.title || "";
        if (title.length === 0) {
            const first = messages.find(m => m && m.role === "user" && (m.rawContent ?? "").length > 0);
            title = first ? root.titleFrom(first.rawContent) : "";
        }
        if (title.length === 0) title = id === root.autosaveAlias ? "Previous conversation" : id;
        const first = messages.length > 0 ? messages[0].timestamp : 0;
        const last = messages.length > 0 ? messages[messages.length - 1].timestamp : 0;
        // `||`, not `??`: a stored `updatedAt: 0` or `sessionId: ""` is a gap to
        // fill, not a value to keep, and a thread row that reads "never saved"
        // is what keeping it looks like.
        return {
            "id": id,
            "title": title,
            "sessionId": meta.sessionId || root.newSessionId(),
            "createdAt": meta.createdAt || first || Date.now(),
            "updatedAt": meta.updatedAt || last || Date.now(),
            "messageCount": messages.length,
            "titleLocked": Boolean(meta.titleLocked),
        };
    }

    // --- mutation -------------------------------------------------------

    function createThread(title) {
        root.ensureIndexLoaded();
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
        root.ensureIndexLoaded();
        if (root.threadFor(root.currentThreadId)) return root.currentThreadId;
        if (root.currentThreadId.length > 0) {
            root._register(root.currentThreadId);
            return root.currentThreadId;
        }
        return root.createThread("");
    }

    function _register(id) {
        root.ensureIndexLoaded();
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
        root.lastActiveId = id;
    }

    /**
     * The thread a name refers to. `lastSession` is the alias every autosave
     * still writes under, so on the way back in it means the thread that was
     * open — not a file that happens to be called that.
     */
    function resolve(name) {
        const id = (name ?? "").trim();
        if (id !== root.autosaveAlias) return id;
        if (root.threadFor(id)) return id;
        return root.lastActiveId.length > 0 ? root.lastActiveId : id;
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

    Component.onCompleted: {
        if (!root.active) return;
        root.ensureIndexLoaded();
        root.refresh();
    }
}
