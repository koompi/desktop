pragma Singleton

import QtQuick
import qs.services
import Quickshell
import Quickshell.Io

/**
 * Whether a screen recording is running.
 *
 * wf-recorder is started detached by scripts/videos/record.sh and can be stopped
 * from a keybind, the toolbar or by dying on its own, so the process itself is
 * the only source that is right in every case.
 */
Singleton {
    id: root

    property bool active: false

    // ponytail: a 2s pidof poll, not a pidfile or a wrapper process. A recording
    // light that lags a second behind is still a recording light.
    Process {
        id: check
        command: ["pidof", "wf-recorder"]
        onExited: exitCode => root.active = (exitCode === 0)
    }

    Timer {
        // The light is on the bar, so there is nothing to keep right while the
        // session is locked -- and that is where the fork mattered, because this
        // is the only unconditional poller in the shell that spawns a process.
        running: PowerSaving.awake
        repeat: true
        interval: PowerSaving.interval(2000)
        triggeredOnStart: true
        onTriggered: if (!check.running)
            check.running = true
    }
}
