pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

/**
 * Puts the desktop back where it was left: the workspace that was focused, and
 * the windows that were open, on the workspaces they were on.
 *
 * The shell owns this rather than Hyprland because window rules can only place
 * a window that already exists - something still has to relaunch the
 * applications, and the shell is the only thing here that already knows both
 * the live client list and which desktop entry a window class came from.
 *
 * Saving is a debounced snapshot of `hyprctl clients`, so a session that ends
 * by crashing still leaves the second-to-last state rather than nothing.
 */
Singleton {
    id: root

    readonly property string filePath: `${Directories.state}/user/session.json`
    readonly property bool enable: Config.options.session?.restore ?? false

    // How long after login a newly opened window may still be claimed as one of
    // ours. Past this, an opening window is the user's own and is left alone.
    readonly property int claimWindowMs: 90000

    // Saved windows still waiting for their application to appear, each
    // { class, workspace }. Claimed entries are removed.
    property var pending: []
    // Snapshots are only written once the restore decision has been made, so
    // the state being replayed is never overwritten before it is read.
    property bool armed: false
    // The session read off disk at startup, and the workspace it was left on.
    property var stateToRestore: null
    property int restoreWorkspace: 0

    // Referenced from shell.qml; singletons are lazy and this one has to exist
    // at login whether or not anything asks it a question.
    function load() {}

    function arm() {
        if (root.armed)
            return;
        // HyprlandData is lazy too, and its client list is empty until its
        // first fetch returns. Asking now means the "is anything open?" test
        // below is answered with the real list rather than that empty one.
        HyprlandData.updateAll();
        startupTimer.restart();
    }

    /**
     * A saved session is only worth replaying when it parses and every field is
     * the shape the writer produced. Anything else - truncated by a crash,
     * hand-edited, written by another version - is discarded, because this runs
     * at login and replaying nonsense means a desktop that fights the user.
     * Returns null for anything unusable.
     */
    function parseState(text) {
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            return null;
        }
        if (!data || typeof data !== "object" || Array.isArray(data))
            return null;
        if (data.version !== 1 || !Array.isArray(data.windows))
            return null;
        if (!root.isWorkspaceId(data.workspace))
            return null;
        // One bad entry discards the whole file rather than being filtered out:
        // a file that is partly wrong is a file of unknown provenance.
        for (const w of data.windows) {
            if (!w || typeof w !== "object" || Array.isArray(w))
                return null;
            if (typeof w.class !== "string" || w.class.length === 0)
                return null;
            if (!root.isWorkspaceId(w.workspace))
                return null;
        }
        return {
            workspace: data.workspace,
            windows: data.windows.map(w => ({
                "class": w["class"],
                workspace: w.workspace
            }))
        };
    }

    function isWorkspaceId(value) {
        return Number.isInteger(value) && value >= 1 && value <= 100;
    }

    function snapshot() {
        // Workspace ids outside 1..100 are special workspaces and the lock
        // screen's temporary one; neither is somewhere to put a window back.
        const windows = HyprlandData.windowList.filter(w => w?.class?.length > 0 && root.isWorkspaceId(w.workspace?.id)).map(w => ({
            "class": w["class"],
            workspace: w.workspace.id
        }));
        return {
            version: 1,
            workspace: root.isWorkspaceId(HyprlandData.activeWorkspace?.id) ? HyprlandData.activeWorkspace.id : 1,
            windows: windows
        };
    }

    function save() {
        if (!root.armed || !root.enable)
            return;
        stateFileView.setText(JSON.stringify(root.snapshot()));
    }

    function replay(state) {
        root.restoreWorkspace = state.workspace;
        Hyprland.dispatch(`hl.dsp.focus({ workspace = ${state.workspace} })`);

        const queue = [];
        for (const window of state.windows) {
            // No desktop entry means no way to relaunch it. Skipping is the
            // whole handling: no placeholder, no message, no delay.
            const entry = DesktopEntries.heuristicLookup(window["class"]);
            if (!entry)
                continue;
            queue.push(window);
            entry.execute();
        }
        root.pending = queue;
        if (queue.length > 0)
            claimTimer.restart();
        else
            root.restoreWorkspace = 0;
    }

    function claim(address, windowClass, openedOn) {
        const index = root.pending.findIndex(w => w["class"].toLowerCase() === windowClass.toLowerCase());
        if (index < 0)
            return;
        const target = root.pending[index].workspace;
        const remaining = root.pending.slice();
        remaining.splice(index, 1);
        root.pending = remaining;

        if (String(target) !== openedOn)
            Hyprland.dispatch(`hl.dsp.window.move({ workspace = ${target}, follow = false, window = "address:0x${address}" })`);
        if (remaining.length === 0)
            root.finishRestore();
    }

    function finishRestore() {
        claimTimer.stop();
        root.pending = [];
        // The last window to open takes focus with it, so the workspace the
        // session was left on is asked for once more now that nothing else is
        // about to appear.
        if (root.restoreWorkspace > 0)
            Hyprland.dispatch(`hl.dsp.focus({ workspace = ${root.restoreWorkspace} })`);
        root.restoreWorkspace = 0;
    }

    Timer {
        id: claimTimer
        interval: root.claimWindowMs
        repeat: false
        onTriggered: root.finishRestore()
    }

    // Long enough for Hyprland to have restored any windows of its own and for
    // the client list to have been fetched once.
    Timer {
        id: startupTimer
        interval: 2000
        repeat: false
        onTriggered: {
            // A shell restarted in the middle of a session must not relaunch
            // the session: only a desktop with nothing open on it is a login.
            if (root.enable && root.stateToRestore && HyprlandData.windowList.length === 0)
                root.replay(root.stateToRestore);
            else
                root.stateToRestore = null;
            root.armed = true;
        }
    }

    Timer {
        id: saveTimer
        interval: 3000
        repeat: false
        onTriggered: root.save()
    }

    Connections {
        target: Hyprland

        function onRawEvent(event) {
            if (!root.enable)
                return;
            if (event.name === "openwindow" && root.pending.length > 0) {
                // WINDOWADDRESS,WORKSPACENAME,WINDOWCLASS,WINDOWTITLE - the
                // title can hold commas, the three fields before it cannot.
                const parts = event.data.split(",");
                if (parts.length >= 3)
                    root.claim(parts[0], parts[2], parts[1]);
            }
            if (["openwindow", "closewindow", "movewindow", "movewindowv2", "workspace", "workspacev2"].includes(event.name))
                saveTimer.restart();
        }
    }

    FileView {
        id: stateFileView
        path: root.filePath
        // Stated rather than left to the default: a crash partway through a
        // snapshot must leave the previous session readable, not half of two.
        atomicWrites: true
        // Only the state that was on disk before this session began is a
        // candidate; every later load is this service's own snapshot.
        onLoaded: {
            if (!root.armed)
                root.stateToRestore = root.parseState(stateFileView.text());
        }
        onLoadFailed: {
            if (!root.armed)
                root.stateToRestore = null;
        }
    }

    // Enabling mid-session cannot restore anything, but it does have to start
    // saving, or the setting would only take effect a login after it was set.
    onEnableChanged: {
        if (root.enable)
            root.arm();
    }

    Component.onCompleted: {
        if (root.enable)
            root.arm();
    }
}
