pragma Singleton
pragma ComponentBehavior: Bound

// Took many bits from https://github.com/caelestia-dots/shell (GPLv3)

import Quickshell
import QtQuick
import qs.services
import qs.services.network

/**
 * Network state from koompi-shelld, which reads NetworkManager over D-Bus.
 *
 * Every property below is the same one this file published when it drove eleven
 * `nmcli` invocations and a twelfth `nmcli monitor`; the derivations that used to run
 * in JavaScript here are computed in koompi-network and arrive ready. See
 * shell-services/shelld/PROTOCOL.md, which is the contract.
 */
Singleton {
    id: root

    readonly property var state: ShellServices.network

    property bool wifi: root.wifiStatus === "connected"
    property bool ethernet: root.state?.ethernet ?? false

    property bool wifiEnabled: root.state?.wifi?.enabled ?? false
    property bool wifiScanning: root.state?.wifi?.scanning ?? false
    property bool wifiConnecting: (root.state?.wifi?.connecting ?? false) || root.wifiConnectTarget !== null
    property WifiAccessPoint wifiConnectTarget
    readonly property list<WifiAccessPoint> wifiNetworks: []
    readonly property WifiAccessPoint active: wifiNetworks.find(n => n.active) ?? null
    readonly property list<var> friendlyWifiNetworks: [...wifiNetworks].sort((a, b) => {
        if (a.active && !b.active)
            return -1;
        if (!a.active && b.active)
            return 1;
        return b.strength - a.strength;
    })
    property string wifiStatus: root.state?.wifi?.status ?? "disconnected"

    property string networkName: root.state?.network_name ?? ""
    property int networkStrength: root.state?.network_strength ?? 0
    readonly property bool connected: root.state?.connected ?? false

    // NetworkManager answers this outright; nmcli never could, which is why
    // openPublicWifiPortal exists at all.
    readonly property bool captivePortal: root.state?.captive_portal ?? false

    property string materialSymbol: root.ethernet
        ? "lan"
        : (root.wifiEnabled && root.wifiStatus === "connected")
            ? (
                (root.active?.strength ?? 0) > 83 ? "signal_wifi_4_bar" :
                (root.active?.strength ?? 0) > 67 ? "network_wifi" :
                (root.active?.strength ?? 0) > 50 ? "network_wifi_3_bar" :
                (root.active?.strength ?? 0) > 33 ? "network_wifi_2_bar" :
                (root.active?.strength ?? 0) > 17 ? "network_wifi_1_bar" :
                "signal_wifi_0_bar"
            )
            : (root.wifiStatus === "connecting")
                ? "signal_wifi_statusbar_not_connected"
                : (root.wifiStatus === "disconnected")
                    ? "signal_wifi_off"
                    : (root.wifiStatus === "disabled")
                        ? "wifi_off"
                        : "signal_wifi_bad"

    // Control
    function enableWifi(enabled = true): void {
        ShellServices.command("network", "set_wireless_enabled", {
            enabled: enabled
        });
    }

    function toggleWifi(): void {
        enableWifi(!wifiEnabled);
    }

    function rescanWifi(): void {
        ShellServices.command("network", "request_scan");
    }

    function connectToWifiNetwork(accessPoint: WifiAccessPoint): void {
        root._connect(accessPoint, null);
    }

    function disconnectWifiNetwork(): void {
        ShellServices.command("network", "disconnect");
    }

    function openPublicWifiPortal() {
        Quickshell.execDetached(["xdg-open", "https://nmcheck.gnome.org/"]) // From some StackExchange thread, seems to work
    }

    /**
     * The passphrase rides on the connection attempt rather than being written into the
     * saved profile first. `nmcli connection modify` persisted it before anything had
     * checked it, so a typo locked the user out of their own network until the profile
     * was fixed by hand.
     */
    function changePassword(network: WifiAccessPoint, password: string, username = ""): void {
        // TODO: enterprise wifi with username
        root._connect(network, password);
    }

    property int _connectRequest: 0

    function _connect(accessPoint: WifiAccessPoint, passphrase): void {
        if (!accessPoint)
            return;
        accessPoint.askingPassword = false;
        root.wifiConnectTarget = accessPoint;

        const args = {
            path: accessPoint.path
        };
        if (passphrase)
            args.passphrase = passphrase;
        root._connectRequest = ShellServices.command("network", "connect", args);
    }

    Connections {
        target: ShellServices

        function onReplyReceived(id, ok, error) {
            if (id !== root._connectRequest)
                return;
            root._connectRequest = 0;
            const target = root.wifiConnectTarget;
            root.wifiConnectTarget = null;
            if (!target)
                return;
            // `rejected` is NetworkManager declining the credentials, which is what the
            // string "Secrets were required" on nmcli's stderr used to stand in for.
            target.askingPassword = !ok && (error === "rejected" || error === "unavailable");
        }
    }

    // The daemon publishes one row per bssid and one per ssid; this is the second,
    // which is the view this file always showed.
    onStateChanged: root._reconcile(root.state?.wifi?.networks_by_ssid ?? [])

    function _reconcile(rows): void {
        const incoming = rows.map(ap => ({
            path: ap.path,
            active: ap.active,
            strength: ap.strength,
            frequency: ap.frequency,
            ssid: ap.ssid,
            ssidHex: ap.ssid_hex,
            bssid: ap.hw_address,
            security: ap.security.label,
            wantsPsk: ap.security.wants_psk,
            enterprise: ap.security.enterprise,
            bandGhz: ap.band_ghz
        }));

        const existing = root.wifiNetworks;
        // Keyed on the ssid bytes and the radio, not on the object path, which
        // NetworkManager recreates on a rescan. Losing identity here would reset
        // askingPassword and rebuild every delegate in the list.
        const key = n => n.ssidHex + "\0" + n.bssid + "\0" + n.frequency;
        const wanted = new Set(incoming.map(key));

        const destroyed = existing.filter(n => !wanted.has(key(n)));
        for (const network of destroyed)
            existing.splice(existing.indexOf(network), 1).forEach(n => n.destroy());

        for (const network of incoming) {
            const match = existing.find(n => key(n) === key(network));
            if (match)
                match.lastIpcObject = network;
            else
                existing.push(apComp.createObject(root, {
                    lastIpcObject: network
                }));
        }
    }

    Component.onCompleted: ShellServices.subscribe("network")

    Component {
        id: apComp

        WifiAccessPoint {}
    }
}
