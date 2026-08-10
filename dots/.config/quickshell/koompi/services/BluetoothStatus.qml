pragma Singleton
pragma ComponentBehavior: Bound

import qs.services
import Quickshell
import QtQuick

/**
 * Adapters and devices, from koompi-shelld's `bluetooth` service.
 *
 * The delta over `Quickshell.Bluetooth` is the rfkill step. A ThinkPad radio switch can
 * soft-block bluetooth, and BlueZ then answers a `Powered = true` with success and leaves
 * the adapter off: the toggle looked dead. The daemon clears the block first, as an 8-byte
 * write to `/dev/rfkill` rather than the `rfkill unblock bluetooth` fork this file used to
 * run before every power-on, and it can tell a soft block from a hardware switch.
 *
 * Devices are plain objects off the wire, so an action is a call here rather than a method
 * on the device. Ordering them is presentation and stays here; the daemon publishes the
 * fields to order by.
 */
Singleton {
    id: root

    readonly property var snapshot: ShellServices.bluetooth
    readonly property var adapter: root.snapshot?.adapter ?? null

    readonly property bool available: root.snapshot?.available ?? false
    readonly property bool enabled: root.snapshot?.powered ?? false
    readonly property bool discovering: root.snapshot?.discovering ?? false
    readonly property bool connected: root.snapshot?.connected ?? false

    readonly property var devices: root.snapshot?.devices ?? []
    readonly property int activeDeviceCount: root.snapshot?.connected_count ?? 0
    readonly property var firstActiveDevice: root.devices.find(device => device.connected) ?? null

    function setEnabled(on) {
        ShellServices.command("bluetooth", "set_powered", {
            powered: on
        });
    }

    function setDiscovering(on) {
        ShellServices.command("bluetooth", "set_discovering", {
            discovering: on
        });
    }

    function connectDevice(device) {
        root._device("connect", device);
    }

    function disconnectDevice(device) {
        root._device("disconnect", device);
    }

    function pair(device) {
        root._device("pair", device);
    }

    function forget(device) {
        root._device("forget", device);
    }

    function _device(cmd, device) {
        if (!device?.path)
            return;
        ShellServices.command("bluetooth", cmd, {
            device: device.path
        });
    }

    function sortFunction(a, b) {
        // Ones with meaningful names before MAC addresses. `alias` falls back to the
        // dashed address precisely when BlueZ never learned a name, so the absent `name`
        // is the test rather than the shape of the string.
        if (!a.name !== !b.name)
            return a.name ? -1 : 1;

        return a.alias.localeCompare(b.alias);
    }
    readonly property var connectedDevices: root.devices.filter(d => d.connected).sort(root.sortFunction)
    readonly property var pairedButNotConnectedDevices: root.devices.filter(d => d.paired && !d.connected).sort(root.sortFunction)
    readonly property var unpairedDevices: root.devices.filter(d => !d.paired && !d.connected).sort(root.sortFunction)
    readonly property var friendlyDeviceList: [
        ...root.connectedDevices,
        ...root.pairedButNotConnectedDevices,
        ...root.unpairedDevices
    ]

    Component.onCompleted: ShellServices.subscribe("bluetooth")
}
