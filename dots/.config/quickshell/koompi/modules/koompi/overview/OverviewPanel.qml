import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

// The workspace grid. It owns GlobalStates.overviewOpen and reads no other
// panel's flag, so search opening or closing never moves this window.
Scope {
    id: root

    // Shares the search surface's layer namespace; see SearchPanel.qml.
    readonly property string layerNamespace: "quickshell:overview"

    function close() {
        GlobalStates.overviewOpen = false;
    }

    function toggle() {
        GlobalStates.overviewOpen = !GlobalStates.overviewOpen;
    }

    PanelWindow {
        id: overviewWindow
        visible: GlobalStates.overviewOpen

        WlrLayershell.namespace: root.layerNamespace
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: GlobalStates.overviewOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        mask: Region {
            item: GlobalStates.overviewOpen ? overviewLayout : null
        }

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        onVisibleChanged: {
            if (overviewWindow.visible) {
                GlobalFocusGrab.addDismissable(overviewWindow);
            } else {
                GlobalFocusGrab.removeDismissable(overviewWindow);
            }
        }

        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                root.close();
            }
        }

        implicitWidth: overviewLayout.implicitWidth
        implicitHeight: overviewLayout.implicitHeight

        Column {
            id: overviewLayout
            visible: GlobalStates.overviewOpen
            anchors {
                horizontalCenter: parent.horizontalCenter
                top: parent.top
            }

            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                }
            }

            Loader {
                id: overviewLoader
                anchors.horizontalCenter: parent.horizontalCenter
                active: GlobalStates.overviewOpen && (Config?.options.overview.enable ?? true)
                sourceComponent: OverviewWidget {
                    screen: overviewWindow.screen
                }
            }
        }
    }

    GlobalShortcut {
        name: "overviewWorkspacesClose"
        description: "Closes overview on press"

        onPressed: {
            root.close();
        }
    }

    GlobalShortcut {
        name: "overviewWorkspacesToggle"
        description: "Toggles overview on press"

        onPressed: {
            root.toggle();
        }
    }
}
