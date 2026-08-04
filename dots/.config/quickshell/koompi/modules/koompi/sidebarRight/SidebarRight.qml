import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope {
    id: root
    property int sidebarWidth: Appearance.sizes.sidebarWidthRight

    readonly property bool pinned: Persistent.states.sidebar.pinned

    // Held until the content exists: opening from a closed sidebar creates the
    // Loader's item in the same call, but keepRightSidebarLoaded makes that order
    // vary, so the page is applied from onLoaded as well.
    property string pendingDrawer: ""

    function showDrawer(page: string): void {
        const content = sidebarContentLoader.item;
        if (content && content.drawer === page) {
            content.drawer = "";
            panelWindow.hide();
            return;
        }
        root.pendingDrawer = page;
        GlobalStates.sidebarRightOpen = true;
        if (sidebarContentLoader.item) {
            sidebarContentLoader.item.drawer = root.pendingDrawer;
            root.pendingDrawer = "";
        }
    }

    PanelWindow {
        id: panelWindow
        visible: GlobalStates.sidebarRightOpen || root.pinned

        function hide() {
            if (root.pinned)
                return;
            GlobalStates.sidebarRightOpen = false;
        }

        // Reserve up to the panel's visible edge, not the whole window: the left
        // elevationMargin is shadow room, and reserving it too doubles the gap.
        exclusiveZone: root.pinned ? sidebarWidth - Appearance.sizes.elevationMargin : 0
        implicitWidth: sidebarWidth
        WlrLayershell.namespace: "quickshell:sidebarRight"
        WlrLayershell.keyboardFocus: GlobalStates.sidebarRightOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        anchors {
            top: true
            right: true
            bottom: true
        }

        // A pinned panel is not dismissable, so clicking away leaves it alone.
        function updateDismissable() {
            if (panelWindow.visible && !root.pinned) {
                GlobalFocusGrab.addDismissable(panelWindow);
            } else {
                GlobalFocusGrab.removeDismissable(panelWindow);
            }
        }
        onVisibleChanged: updateDismissable()
        Connections {
            target: root
            function onPinnedChanged() {
                panelWindow.updateDismissable();
                if (root.pinned)
                    GlobalStates.sidebarRightOpen = true;
            }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                panelWindow.hide();
            }
        }

        Loader {
            id: sidebarContentLoader
            active: GlobalStates.sidebarRightOpen || root.pinned || Config?.options.sidebar.keepRightSidebarLoaded
            anchors {
                fill: parent
                margins: Appearance.sizes.hyprlandGapsOut
                leftMargin: Appearance.sizes.elevationMargin
            }
            width: sidebarWidth - Appearance.sizes.hyprlandGapsOut - Appearance.sizes.elevationMargin
            height: parent.height - Appearance.sizes.hyprlandGapsOut * 2

            focus: GlobalStates.sidebarRightOpen
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    if (sidebarContentLoader.item?.drawer.length > 0) {
                        sidebarContentLoader.item.drawer = "";
                        return;
                    }
                    panelWindow.hide();
                }
            }

            sourceComponent: SidebarRightContent {}

            onLoaded: {
                if (root.pendingDrawer.length > 0) {
                    item.drawer = root.pendingDrawer;
                    root.pendingDrawer = "";
                }
            }
        }
    }

    IpcHandler {
        target: "sidebarRight"

        function toggle(): void {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }

        function close(): void {
            GlobalStates.sidebarRightOpen = false;
        }

        function open(): void {
            GlobalStates.sidebarRightOpen = true;
        }

        function drawer(page: string): void {
            root.showDrawer(page);
        }
    }

    GlobalShortcut {
        name: "sidebarRightToggle"
        description: "Toggles right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = !GlobalStates.sidebarRightOpen;
        }
    }
    GlobalShortcut {
        name: "sidebarRightOpen"
        description: "Opens right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = true;
        }
    }
    GlobalShortcut {
        name: "sidebarRightClose"
        description: "Closes right sidebar on press"

        onPressed: {
            GlobalStates.sidebarRightOpen = false;
        }
    }

    GlobalShortcut {
        name: "sidebarRightControls"
        description: "Opens the right sidebar on all controls"

        onPressed: root.showDrawer("controls")
    }
    GlobalShortcut {
        name: "sidebarRightCalendar"
        description: "Opens the right sidebar on the calendar"

        onPressed: root.showDrawer("calendar")
    }
    GlobalShortcut {
        name: "sidebarRightTodo"
        description: "Opens the right sidebar on the to-do list"

        onPressed: root.showDrawer("todo")
    }
    GlobalShortcut {
        name: "sidebarRightTimer"
        description: "Opens the right sidebar on the timer"

        onPressed: root.showDrawer("timer")
    }
}
