pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// SearchDaemon.qml - owns the single `searchd` process for the shell session,
// mirroring GlobalMenuService.qml's Process lifecycle (spawn once, running:
// true, restart 3s after any exit). Only FileSearch.qml routes through this;
// Cliphist.qml and AppSearch.qml are untouched - see
// scripts/searchd/PROTOCOL.md for why "clipboard"/"apps" exist in the wire
// protocol but are not consumed here.
//
// Falls back cleanly: FileSearch.qml checks `connected && filesReady` before
// routing a query here, so a daemon that never started, crashed, or is still
// walking $HOME just leaves the existing fd-based path doing what it always
// did.
Singleton {
    id: root

    property bool connected: false
    property bool filesReady: false
    property int filesEntryCount: 0

    property int nextId: 1
    // Per-service "the newest request id issued" - a reply older than this
    // for its own service is a superseded query and is discarded. Same shape
    // as GlobalMenuService.qml's `generation` field.
    property var lastIssuedId: ({ files: 0, clipboard: 0, apps: 0 })
    // id -> {service, callback}, removed once its reply (or a newer
    // supersession) has been handled.
    property var pending: ({})

    readonly property string zigDaemonBin: {
        const url = Qt.resolvedUrl("../scripts/searchd/zig-out/bin/searchd");
        return url.toString().replace("file://", "");
    }

    // Referenced once from shell.qml purely to force this singleton to
    // instantiate - QML singletons are created lazily on first access, and
    // nothing else in the shell touches SearchDaemon before FileSearch.qml's
    // first query. A no-op beyond that.
    function load(): void {}

    /// Returns false without sending anything if the daemon isn't usable
    /// right now - the caller's own job to fall back when this happens.
    function search(service: string, query: string, limit: int, callback: var): bool {
        if (!root.connected)
            return false;
        const id = root.nextId++;
        root.lastIssuedId[service] = id;
        root.pending[id] = { service: service, callback: callback };
        daemon.write(JSON.stringify({ cmd: "search", id: id, service: service, query: query, limit: limit }) + "\n");
        return true;
    }

    /// Fire-and-forget: replaces `service`'s whole dataset. Silently a no-op
    /// if the daemon isn't connected - the next successful `update` after
    /// reconnect carries the current data anyway.
    function updateDataset(service: string, entries: var): void {
        if (!root.connected)
            return;
        const id = root.nextId++;
        root.pending[id] = { service: service, callback: (msg) => {
            if (!msg.ok)
                console.error("[SearchDaemon] update", service, "failed:", msg.error, msg.message);
        } };
        daemon.write(JSON.stringify({ cmd: "update", id: id, service: service, entries: entries }) + "\n");
    }

    Process {
        id: daemon
        command: [root.zigDaemonBin]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                let msg;
                try {
                    msg = JSON.parse(line);
                } catch (e) {
                    return;
                }

                if (msg.type === "hello") {
                    root.connected = true;
                    return;
                }
                if (msg.type === "state") {
                    if (msg.service === "files") {
                        root.filesReady = msg.ready === true;
                        root.filesEntryCount = msg.entryCount ?? 0;
                    }
                    return;
                }
                if (msg.type === "reply" && msg.id !== null && msg.id !== undefined) {
                    const entry = root.pending[msg.id];
                    if (!entry)
                        return;
                    delete root.pending[msg.id];
                    // Superseded by a newer request for the same service
                    // issued after this one - the newer reply is still on
                    // its way (the daemon answers in arrival order), so
                    // dropping this one loses nothing.
                    if (msg.id < root.lastIssuedId[entry.service])
                        return;
                    entry.callback(msg);
                }
            }
        }

        onRunningChanged: {
            if (!running) {
                root.connected = false;
                root.filesReady = false;
                root.pending = ({});
                restartTimer.start();
            }
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: daemon.running = true
    }
}
