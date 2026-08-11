pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The one koompi-shelld the shell runs, multiplexing every Rust service behind it.
// Consumers never spawn their own: the daemon holds a single system bus connection
// and a second copy would open a second one, plus a second NetworkManager client.
//
// The wire format is shell-services/shelld/PROTOCOL.md. That document, not the Rust,
// is what this file is written against.
Singleton {
    id: root

    readonly property string binary: {
        const installed = Quickshell.env("HOME") + "/.local/bin/koompi-shelld";
        const override = Quickshell.env("KOOMPI_SHELLD");
        return override && override.length > 0 ? override : installed;
    }
    readonly property string inTreeBinary: {
        const url = Qt.resolvedUrl("../../../../../shell-services/target/release/koompi-shelld");
        return url.toString().replace("file://", "");
    }

    // Nothing starts until something asks for it, which is the daemon's own rule:
    // subscribing to power activates power-profiles-daemon, and subscribing to
    // network puts NetworkManager to work scanning.
    property var wanted: ({})

    readonly property bool ready: daemon.running && root.protocol > 0
    property int protocol: 0

    property var hyprland: null
    property var network: null
    property var power: null
    property var brightness: null
    property var bluetooth: null

    // A service the daemon could not reach. Absent from this map means healthy;
    // present means the reason it named.
    property var outages: ({})

    signal replyReceived(int id, bool ok, string error)

    property int nextId: 1

    function subscribe(service) {
        if (root.wanted[service])
            return;
        root.wanted[service] = true;
        root.wanted = root.wanted;
        if (root.ready)
            root.send({
                cmd: "subscribe",
                services: [service]
            });
    }

    /// Returns the request id, so a caller that cares can match `replyReceived`.
    function send(message) {
        const id = root.nextId++;
        message.id = id;
        if (daemon.running)
            daemon.write(JSON.stringify(message) + "\n");
        else
            root.replyReceived(id, false, "unavailable");
        return id;
    }

    function command(service, cmd, args) {
        const message = args ? Object.assign({}, args) : ({});
        message.cmd = cmd;
        message.service = service;
        return root.send(message);
    }

    /// The panel driving a screen, by the connector name `Quickshell.screens` uses.
    function brightnessPanel(connector) {
        return root.brightness?.panels?.find(panel => panel.connector === connector) ?? null;
    }

    function outageOf(service) {
        return root.outages[service] ?? "";
    }

    function _handle(payload) {
        switch (payload.type) {
        case "hello":
            root.protocol = payload.protocol ?? 0;
            const services = Object.keys(root.wanted);
            if (services.length > 0)
                root.send({
                    cmd: "subscribe",
                    services: services
                });
            break;
        case "state":
            if (root.outages[payload.service] !== undefined) {
                delete root.outages[payload.service];
                root.outages = root.outages;
            }
            if (payload.service === "hyprland")
                root.hyprland = payload.state;
            else if (payload.service === "network")
                root.network = payload.state;
            else if (payload.service === "power")
                root.power = payload.state;
            else if (payload.service === "brightness")
                root.brightness = payload.state;
            else if (payload.service === "bluetooth")
                root.bluetooth = payload.state;
            break;
        case "unavailable":
            root.outages[payload.service] = payload.reason;
            root.outages = root.outages;
            break;
        case "reply":
            root.replyReceived(payload.id ?? 0, payload.ok === true, payload.error ?? "");
            break;
        }
    }

    Process {
        id: daemon
        // Prefer what setups.sh installed, fall back to a release build in the tree,
        // the resolution GlobalMenuService.qml:14-21 already performs for its own.
        command: ["bash", "-c", 'if [ -x "$1" ]; then exec "$1"; fi; exec "$2"', "bash", root.binary, root.inTreeBinary]
        running: true
        stdinEnabled: true

        stdout: SplitParser {
            onRead: line => {
                let payload;
                try {
                    payload = JSON.parse(line);
                } catch (e) {
                    return;
                }
                root._handle(payload);
            }
        }

        stderr: SplitParser {
            onRead: line => console.error("[ShellServices]", line)
        }

        onRunningChanged: {
            if (daemon.running)
                return;
            // The daemon owns the connection, so its state went with it. Clearing
            // rather than keeping the last snapshot is deliberate: a bar drawing a
            // network that is no longer being watched is worse than one drawing none.
            root.protocol = 0;
            root.hyprland = null;
            root.network = null;
            root.power = null;
            root.brightness = null;
            root.bluetooth = null;
            restartTimer.start();
        }
    }

    Timer {
        id: restartTimer
        interval: 3000
        onTriggered: daemon.running = true
    }
}
