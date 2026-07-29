pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Overlay-layer dismiss surface for scratchpad windows.
//
// WlrLayer.Overlay sits above every app window and the bar, so ALL pointer
// events outside the scratchpad reach us. A Region mask with Intersection.Subtract
// punches a hole over the scratchpad window so it stays interactive. TapHandler
// on the overlay closes the scratchpad on any click/tap outside the hole.
//
// Tradeoff: the first click on the bar or another window while a scratchpad is
// open closes the scratchpad (that click is consumed). Click again to interact.
// This matches Super+/ overlay UX.
Scope {
    id: root

    readonly property var managedSpecials: [
        "special:telegram", "special:discord", "special:whatsapp",
        "special:term", "special:sysmon"
    ]

    // monitorName -> wsName (e.g. "eDP-1" -> "special:telegram")
    property var activeSpecials: ({})

    // Seed state on startup: a scratchpad may already be open
    Process {
        running: true
        command: ["hyprctl", "-j", "monitors"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const monitors = JSON.parse(text)
                    const s = {}
                    for (const m of monitors) {
                        const ws = m.specialWorkspace?.name ?? ""
                        if (ws && root.managedSpecials.includes(ws)) s[m.name] = ws
                    }
                    if (Object.keys(s).length > 0) root.activeSpecials = s
                } catch(e) {}
            }
        }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name !== "activespecial") return
            const data = event.data
            const sep = data.lastIndexOf(",")
            const wsName = sep >= 0 ? data.slice(0, sep) : ""
            const monName = sep >= 0 ? data.slice(sep + 1) : data
            const s = Object.assign({}, root.activeSpecials)
            if (wsName && root.managedSpecials.includes(wsName)) {
                s[monName] = wsName
            } else {
                delete s[monName]
            }
            root.activeSpecials = s
        }
    }

    Variants {
        model: Quickshell.screens

        LazyLoader {
            id: dismissLoader
            required property ShellScreen modelData

            property HyprlandMonitor monitor: Hyprland.monitorFor(dismissLoader.modelData)
            property string activeWsName: root.activeSpecials[dismissLoader.monitor?.name ?? ""] ?? ""

            active: dismissLoader.activeWsName !== ""

            component: PanelWindow {
                id: dismissWin
                screen: dismissLoader.modelData

                // Scratchpad window rect in global (compositor) coordinates.
                // Default is a huge rect so the subtract covers the whole screen
                // (= no input blocked) until real geometry is loaded.
                property int scratchX: dismissLoader.monitor?.x ?? 0
                property int scratchY: dismissLoader.monitor?.y ?? 0
                property int scratchW: 9999
                property int scratchH: 9999

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
                WlrLayershell.namespace: "quickshell:scratchpadDismiss"
                exclusionMode: ExclusionMode.Ignore
                color: "transparent"
                anchors { top: true; bottom: true; left: true; right: true }

                // Full-screen input mask with a hole punched over the scratchpad.
                // Events inside the hole pass through to the scratchpad itself.
                // Events outside reach TapHandler → dismiss.
                // While scratchW/H = 9999 (before geometry loads), the subtract
                // covers the whole screen so the overlay is fully passthrough.
                mask: Region {
                    width: dismissWin.width
                    height: dismissWin.height
                    Region {
                        x: dismissWin.scratchX - (dismissLoader.monitor?.x ?? 0)
                        y: dismissWin.scratchY - (dismissLoader.monitor?.y ?? 0)
                        width: dismissWin.scratchW
                        height: dismissWin.scratchH
                        intersection: Intersection.Subtract
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        const ws = dismissLoader.activeWsName
                        if (ws) Hyprland.dispatch(`hl.dsp.workspace.toggle_special("${ws.replace("special:", "")}")`)
                    }
                }

                Process {
                    id: geomQuery
                    command: ["hyprctl", "-j", "clients"]
                    stdout: StdioCollector {
                        id: geomData
                        onStreamFinished: {
                            try {
                                const clients = JSON.parse(geomData.text)
                                const ws = dismissLoader.activeWsName
                                const client = clients.find(c => c.workspace?.name === ws)
                                if (client) {
                                    dismissWin.scratchX = client.at[0]
                                    dismissWin.scratchY = client.at[1]
                                    dismissWin.scratchW = client.size[0]
                                    dismissWin.scratchH = client.size[1]
                                }
                            } catch(e) {}
                        }
                    }
                }

                // Short delay so Hyprland finishes placing the window before we query
                Timer {
                    id: geomTimer
                    interval: 80
                    onTriggered: {
                        geomQuery.running = false
                        geomQuery.running = true
                    }
                }

                Component.onCompleted: geomTimer.start()

                // Re-query if the scratchpad window moves or resizes
                Connections {
                    target: Hyprland
                    function onRawEvent(event) {
                        if (event.name === "movewindow" || event.name === "movewindowv2") {
                            geomTimer.restart()
                        }
                    }
                }
            }
        }
    }
}
