pragma Singleton

import QtQuick
import Quickshell
import qs.services

/**
 * UPower's battery charge limit: stop charging at endThreshold, resume at
 * startThreshold. Keeps a Li-poly pack off a permanent 100% float.
 *
 * koompi-power reads the four properties over D-Bus and koompi-shelld publishes them,
 * so the `busctl` fork this file used to carry is gone along with the reason for it:
 * Quickshell 0.2.1 shipping no generic D-Bus client. The polkit action allows an
 * active local session, so there is still no agent and no prompt.
 */
Singleton {
    id: root

    readonly property var threshold: ShellServices.power?.primary?.threshold ?? null

    // `supported` false covers both a pack without the feature and a UPower below
    // 1.90, which has no such properties at all. Nothing here needs to tell them apart.
    readonly property bool supported: root.threshold?.supported ?? false
    property bool enabled: root.threshold?.enabled ?? false
    readonly property int startThreshold: root.threshold?.start ?? 0
    readonly property int endThreshold: root.threshold?.end ?? 0

    onThresholdChanged: root.enabled = root.threshold?.enabled ?? false

    function setEnabled(value) {
        if (!root.supported || value === root.enabled)
            return;
        root.enabled = value; // answer the switch now, the next state confirms
        ShellServices.command("power", "set_charge_threshold_enabled", {
            enabled: value
        });
    }

    Component.onCompleted: ShellServices.subscribe("power")
}
