import qs
import qs.modules.common
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

Scope {
    id: launchpadScope

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.launchpadOpen

        // Opens where the user is looking. Resolved on the way in rather than
        // bound live, so the surface never migrates mid-session.
        property var targetScreen: Quickshell.screens[0] ?? null
        screen: targetScreen

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore
        WlrLayershell.namespace: "quickshell:launchpad"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.launchpadOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Connections {
            target: GlobalStates
            function onLaunchpadOpenChanged() {
                if (GlobalStates.launchpadOpen) {
                    panelWindow.targetScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null;
                    content.reset();
                }
            }
        }

        LaunchpadContent {
            id: content
            anchors.fill: parent
            active: GlobalStates.launchpadOpen
        }
    }

    IpcHandler {
        target: "launchpad"

        function toggle() {
            GlobalStates.launchpadOpen = !GlobalStates.launchpadOpen;
        }
        function open() {
            GlobalStates.launchpadOpen = true;
        }
        function close() {
            GlobalStates.launchpadOpen = false;
        }
    }

    GlobalShortcut {
        name: "launchpadToggle"
        description: "Toggles the Launchpad app grid"

        onPressed: {
            GlobalStates.launchpadOpen = !GlobalStates.launchpadOpen;
        }
    }

    // Open and close are separate so the pinch-in / pinch-out pair is not a
    // toggle: pinching in twice should leave it open, not flap it shut.
    GlobalShortcut {
        name: "launchpadOpen"
        description: "Opens the Launchpad app grid"

        onPressed: {
            GlobalStates.launchpadOpen = true;
        }
    }

    GlobalShortcut {
        name: "launchpadClose"
        description: "Closes the Launchpad app grid"

        onPressed: {
            GlobalStates.launchpadOpen = false;
        }
    }
}
