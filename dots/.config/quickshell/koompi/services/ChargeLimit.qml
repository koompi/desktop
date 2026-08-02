pragma Singleton

import Quickshell
import Quickshell.Io
import Quickshell.Services.UPower

/**
 * UPower's battery charge limit: stop charging at ChargeEndThreshold, resume at
 * ChargeStartThreshold. Keeps a Li-poly pack off a permanent 100% float.
 *
 * ponytail: busctl through Process is the ceiling. Quickshell 0.2.1 ships no
 * generic D-Bus client and its UPower binding stops short of these properties,
 * so there is nothing to bind to. Replace both Processes with bindings the day
 * upstream exposes them.
 * The polkit action allows an active local session, so no agent and no prompt.
 */
Singleton {
    id: root

    // UPower names the object after the sysfs battery, same one Battery.qml reads.
    readonly property string devicePath: {
        const devList = UPower.devices.values;
        for (let i = 0; i < devList.length; ++i) {
            const dev = devList[i];
            if (dev.isLaptopBattery && dev.nativePath !== "") {
                return `/org/freedesktop/UPower/devices/battery_${dev.nativePath}`;
            }
        }
        return "";
    }

    property bool supported: false
    property bool enabled: false
    property int startThreshold: 0
    property int endThreshold: 0

    onDevicePathChanged: root.fetch()

    function fetch() {
        if (root.devicePath === "")
            return;
        // Build the command here rather than binding it: UPower populates its
        // device list after construction, so this handler and a binding on
        // devicePath wake on the same change in no guaranteed order, and busctl
        // run with the still-empty path fails with nothing to retry it.
        fetchProc.command = ["busctl", "--json=short", "get-property", "org.freedesktop.UPower", root.devicePath, "org.freedesktop.UPower.Device", "ChargeThresholdSupported", "ChargeThresholdEnabled", "ChargeStartThreshold", "ChargeEndThreshold"];
        fetchProc.running = true;
    }

    function setEnabled(value) {
        if (root.devicePath === "" || value === root.enabled)
            return;
        root.enabled = value; // answer the switch now, fetch confirms
        setProc.command = ["busctl", "call", "org.freedesktop.UPower", root.devicePath, "org.freedesktop.UPower.Device", "EnableChargeThreshold", "b", value ? "true" : "false"];
        setProc.running = true;
    }

    Process {
        id: fetchProc
        stdout: StdioCollector {
            id: stateCollector
            onStreamFinished: {
                const lines = stateCollector.text.trim().split("\n");
                if (lines.length < 4) { // UPower below 1.90 has no such properties
                    root.supported = false;
                    return;
                }
                root.supported = JSON.parse(lines[0]).data;
                root.enabled = JSON.parse(lines[1]).data;
                root.startThreshold = JSON.parse(lines[2]).data;
                root.endThreshold = JSON.parse(lines[3]).data;
            }
        }
    }

    Process {
        id: setProc
        onExited: root.fetch()
    }
}
