pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The single data owner for every monitor's global-menu renderer. Keeping the
// daemon here is important: com.canonical.AppMenu.Registrar has one owner, and
// applications must not have to register again when focus changes monitors.
Singleton {
    id: root

    readonly property string daemonBin: {
        const url = Qt.resolvedUrl("../scripts/global-menu/zig-out/bin/global-menu-daemon");
        return url.toString().replace("file://", "");
    }

    property var menuItems: []
    // Lazy submenu contents keyed by the stable daemon item id.
    property var patchedChildren: ({})

    // Renderers use this to close local popup state before adopting a new
    // focused application's menu tree.
    signal menuReset()

    function send(command) {
        if (daemon.running)
            daemon.write(command + "\n");
    }

    function childrenOf(entry) {
        if (!entry)
            return [];
        const patched = root.patchedChildren[entry.id];
        return patched ?? entry.items ?? [];
    }

    function hasChildrenFor(entry) {
        if (!entry)
            return false;
        return entry.sub === true || root.childrenOf(entry).length > 0;
    }

    Process {
        id: daemon
        command: [root.daemonBin]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                let payload;
                try {
                    payload = JSON.parse(line);
                } catch (e) {
                    return;
                }
                if (payload.patch !== undefined) {
                    const next = Object.assign({}, root.patchedChildren);
                    next[payload.patch] = payload.items ?? [];
                    root.patchedChildren = next;
                    return;
                }
                root.menuReset();
                root.patchedChildren = ({});
                root.menuItems = payload.items ?? [];
            }
        }

        onRunningChanged: {
            if (!running) {
                root.menuReset();
                root.patchedChildren = ({});
                root.menuItems = [];
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
