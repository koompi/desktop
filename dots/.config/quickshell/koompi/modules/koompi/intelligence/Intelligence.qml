import qs
import qs.modules.common
import qs.services
import qs.modules.koompi.intelligence
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland

/**
 * The assistant at full size. One engine with the sidebar - every service it
 * touches is the same singleton the sidebar drives - and one boolean deciding
 * whether it is on screen.
 */
Scope {
    id: root

    // The window outlives an open, the content does not. A window built per open
    // is slow to map and has no surface for Escape to reach while it is still
    // coming up; a content tree kept alive while closed holds five panes, a
    // transcript and a memory list for nothing.
    PanelWindow {
        id: window
        visible: GlobalStates.intelligenceOpen

        // Opens where the user is looking, resolved on the way in so the surface
        // never migrates mid-session.
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
        WlrLayershell.namespace: "quickshell:intelligence"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.intelligenceOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        Connections {
            target: GlobalStates
            function onIntelligenceOpenChanged() {
                if (!GlobalStates.intelligenceOpen)
                    return;
                window.targetScreen = Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null;
                MemoryService.load();
                // Same release the sidebar performs. Without it the assistant is
                // told it has no memory and the recalled block never reaches the
                // prompt, however well the recall itself worked.
                Ai.memoryWarmed = true;
            }
        }

        Loader {
            id: contentLoader
            anchors.fill: parent
            active: GlobalStates.intelligenceOpen
            sourceComponent: IntelligenceContent {}
            onLoaded: item.forceActiveFocus()
        }
    }

    IpcHandler {
        target: "intelligence"

        function toggle(): void {
            GlobalStates.intelligenceOpen = !GlobalStates.intelligenceOpen;
        }
        function open(): void {
            GlobalStates.intelligenceOpen = true;
        }
        function close(): void {
            GlobalStates.intelligenceOpen = false;
        }
        function pane(name: string): void {
            const index = ["chat", "threads", "memory", "activity", "context"].indexOf(name);
            if (index < 0)
                return;
            IntelligenceContext.currentPane = index;
            GlobalStates.intelligenceOpen = true;
        }
    }

    GlobalShortcut {
        name: "intelligenceToggle"
        description: "Toggles the full-window Intelligence surface"

        onPressed: {
            GlobalStates.intelligenceOpen = !GlobalStates.intelligenceOpen;
        }
    }

    GlobalShortcut {
        name: "intelligenceOpen"
        description: "Opens the full-window Intelligence surface"

        onPressed: {
            GlobalStates.intelligenceOpen = true;
        }
    }

    GlobalShortcut {
        name: "intelligenceClose"
        description: "Closes the full-window Intelligence surface"

        onPressed: {
            GlobalStates.intelligenceOpen = false;
        }
    }
}
