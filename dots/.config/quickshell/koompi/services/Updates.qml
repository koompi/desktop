pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service. Currently only supports Arch.
 */
Singleton {
    id: root

    property bool available: false
    property alias checking: checkUpdatesProc.running
    property int count: 0
    
    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    // checkupdates syncs a temporary pacman database, so at login it competed
    // with the shell drawing its first frame. Nothing here is urgent - hold off
    // until the desktop has been up long enough to be idle.
    property bool settled: false

    Timer {
        interval: 10 * 60 * 1000
        running: true
        repeat: false
        onTriggered: root.settled = true
    }

    function load() {}
    function refresh() {
        if (!available) return;
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    Timer {
        interval: PowerSaving.interval(Config.options.updates.checkInterval * 60 * 1000)
        repeat: true
        running: root.settled && Config.ready && Config.options.updates.enableCheck
        onTriggered: {
            print("[Updates] Periodic update check due")
            root.refresh();
        }
    }

    Process {
        id: checkAvailabilityProc
        running: root.settled && Config.ready && Config.options.updates.enableCheck
        command: ["which", "checkupdates"]
        onExited: (exitCode, exitStatus) => {
            root.available = (exitCode === 0);
            root.refresh();
        }
    }

    Process {
        id: checkUpdatesProc
        command: ["checkupdates"]
        stdout: StdioCollector {
            id: checkUpdatesCollector
        }
        // checkupdates: 0 lists updates, 2 none, 1 could not check; keep the count on 1
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                root.count = checkUpdatesCollector.text.split("\n").filter(line => line.trim().length > 0).length;
            } else if (exitCode === 2) {
                root.count = 0;
            } else {
                console.warn("[Updates] checkupdates failed with code", exitCode, "and status", exitStatus, "- keeping count", root.count);
            }
        }
    }
}
