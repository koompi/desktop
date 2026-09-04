pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * AI-agent CLI token usage (Claude Code/Codex/Pi), read from a JSON file that
 * koompi-agent-usage-{claude,codex,pi} regenerate on a timer. This service
 * only reads the file - it never writes it, the helper scripts do that with
 * their own read-modify-write so each provider's key survives the others'
 * regeneration.
 *
 * A provider whose key is absent from the file (its CLI isn't installed, or
 * its on-disk format didn't match) is meant to be indistinguishable from "no
 * such provider" - never surfaced as a zeroed entry.
 */
Singleton {
    id: root

    property bool available: false
    property var providers: ({})

    readonly property string filePath: FileUtils.trimFileProtocol(`${Directories.state}/agent-usage.json`)

    // Regeneration competes with nothing urgent, so - same idiom as Updates -
    // it holds off until the desktop has been up long enough to be idle.
    property bool settled: false

    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: false
        onTriggered: root.settled = true
    }

    function refresh() {
        print("[AgentUsage] Regenerating agent-usage.json");
        regenerateProc.running = true;
    }

    function parseUsage(fileContent) {
        let parsed = {};
        try {
            const json = JSON.parse(fileContent);
            if (json && typeof json === "object")
                parsed = json;
        } catch (e) {
            print("[AgentUsage] Failed to parse agent-usage.json: " + e);
        }
        root.providers = parsed;
        root.available = Object.keys(parsed).length > 0;
    }

    // Omarchy's documented cadence for its equivalent widget.
    Timer {
        interval: PowerSaving.interval(15 * 60 * 1000)
        repeat: true
        triggeredOnStart: true
        running: root.settled && Config.ready
        onTriggered: root.refresh()
    }

    Process {
        id: regenerateProc
        command: ["bash", "-c", "koompi-agent-usage-claude; koompi-agent-usage-codex; koompi-agent-usage-pi"]
    }

    FileView {
        id: usageFileView
        path: root.filePath
        watchChanges: true
        // Missing until the first regeneration writes it; onLoadFailed handles that.
        printErrors: false
        onFileChanged: reload()
        onLoadedChanged: root.parseUsage(usageFileView.text())
        onLoadFailed: error => {
            if (error === FileViewError.FileNotFound) {
                root.providers = {};
                root.available = false;
            }
        }
    }
}
