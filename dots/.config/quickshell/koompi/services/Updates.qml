pragma Singleton

import qs.modules.common
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Io

/*
 * System updates service. Currently only supports Arch.
 *
 * KOOMPI_UPDATES_FORCE=N in the shell's environment fakes N pending updates
 * without probing checkupdates; it is how tests/test_bar_keys.sh captures the
 * bar badge on a headless instance, and is never set for the live shell.
 */
Singleton {
    id: root

    readonly property int forced: parseInt(Quickshell.env("KOOMPI_UPDATES_FORCE") ?? "", 10) || 0

    property bool available: root.forced > 0
    property alias checking: checkUpdatesProc.running
    property int count: root.forced
    
    readonly property bool updateAdvised: available && count > Config.options.updates.adviseUpdateThreshold
    readonly property bool updateStronglyAdvised: available && count > Config.options.updates.stronglyAdviseUpdateThreshold

    // checkupdates syncs a temporary pacman database, so at login it competed
    // with the shell drawing its first frame. Nothing here is urgent - hold off
    // until the desktop has been up long enough to be idle. That first check,
    // ten minutes into the session, is the "at session start" one; the timer
    // below carries on from there.
    property bool settled: false

    // A low battery is spent on keeping the session up, not on syncing a
    // pacman database that the bar can show later just as well.
    readonly property bool batteryTooLow: Battery.isLow && !Battery.isCharging

    Timer {
        interval: 10 * 60 * 1000
        running: root.forced === 0
        repeat: false
        onTriggered: root.settled = true
    }

    function load() {}
    function refresh() {
        if (!available || root.forced > 0) return;
        if (root.batteryTooLow) {
            print("[Updates] Battery low, skipping the update check");
            return;
        }
        print("[Updates] Checking for system updates")
        checkUpdatesProc.running = true;
    }

    // Config.options.updates.checkInterval; the default is six hours because
    // the Arch mirrors' package databases refresh a few times a day, so a
    // shorter interval mostly re-syncs the same index for the same answer.
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
