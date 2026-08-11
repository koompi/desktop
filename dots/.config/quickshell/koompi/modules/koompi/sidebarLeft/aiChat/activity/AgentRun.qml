pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The live state of the one agent run `agent.sh` allows at a time, read from the
 * files that run writes: `status` is six lines of state, `task` is the question,
 * `output` grows while pi works. Cancelling goes back through the same script,
 * which owns the process group and is the only thing that can kill the child.
 */
Singleton {
    id: root

    readonly property string runDirectory: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") ?? "";
        return `${runtime.length > 0 ? runtime : "/tmp"}/quickshell/ai/agent`;
    }
    readonly property string scriptPath: `${Directories.scriptPath}/ai/agent.sh`.replace(/file:\/\//, "")

    property string state: "idle"
    property real startedMs: 0
    property real finishedMs: 0
    property int timeoutSec: 240
    property string task: ""
    property string output: ""
    property bool cancelling: false

    readonly property bool running: root.state === "running"
    property real nowMs: Date.now()
    readonly property real elapsedMs: root.startedMs <= 0 ? 0
        : Math.max(0, (root.running ? root.nowMs : root.finishedMs) - root.startedMs)
    readonly property real progress: root.timeoutSec <= 0 ? 0
        : Math.min(1, root.elapsedMs / (root.timeoutSec * 1000))

    function cancel() {
        if (!root.running) return;
        root.cancelling = true;
        cancelProc.running = true;
    }

    function _readStatus(text: string) {
        const lines = String(text).split("\n");
        const state = (lines[0] ?? "").trim();
        if (state.length === 0) return;
        root.startedMs = Number(lines[1] ?? 0);
        root.finishedMs = Number(lines[2] ?? 0);
        root.timeoutSec = Number(lines[5] ?? 240);
        if (state !== "running") root.cancelling = false;
        root.state = state;
    }

    readonly property Process cancelProc: Process {
        command: [root.scriptPath, "--cancel"]
    }

    // A run writes these files a few times a second; a poll while one is in
    // flight is cheaper and steadier than a watch that fires on every delta.
    readonly property Timer poll: Timer {
        interval: 400
        repeat: true
        running: root.running || Ai.toolStatusLabel.length > 0
        triggeredOnStart: true
        onTriggered: {
            root.nowMs = Date.now();
            statusFile.reload();
            taskFile.reload();
            outputFile.reload();
        }
    }

    readonly property FileView statusFile: FileView {
        path: `${root.runDirectory}/status`
        printErrors: false
        onLoaded: root._readStatus(statusFile.text())
    }

    readonly property FileView taskFile: FileView {
        path: `${root.runDirectory}/task`
        printErrors: false
        onLoaded: root.task = taskFile.text().trim()
    }

    readonly property FileView outputFile: FileView {
        path: `${root.runDirectory}/output`
        printErrors: false
        onLoaded: root.output = outputFile.text()
    }
}
