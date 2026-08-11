import qs.modules.common
import qs.modules.koompi.sidebarLeft.aiChat.memory
import qs.modules.common.functions
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * The memory browser as a window of its own, so the store is readable before
 * the full assistant window exists. `qs ipc call memory toggle` opens it.
 */
PanelWindow {
    id: window

    visible: true
    screen: Quickshell.screens.find(s => s.name === Hyprland.focusedMonitor?.name) ?? Quickshell.screens[0] ?? null

    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: Appearance.colors.colScrim
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "quickshell:memoryBrowser"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Closes on a click beside the card. The test is on the position rather than
    // on a swallowing MouseArea under the card: anything in the card that is not
    // itself interactive falls through to here, and a click on the panel's own
    // background must not close it.
    MouseArea {
        anchors.fill: parent
        onClicked: event => {
            const local = card.mapFromItem(null, event.x, event.y);
            if (local.x < 0 || local.y < 0 || local.x > card.width || local.y > card.height) MemoryService.closeBrowser();
        }
    }

    Item {
        id: card
        anchors.centerIn: parent
        implicitWidth: Math.min(720, window.width - Appearance.sizes.elevationMargin * 8)
        implicitHeight: Math.min(820, window.height - Appearance.sizes.elevationMargin * 8)

        focus: true
        Keys.onEscapePressed: MemoryService.closeBrowser()

        MemoryBrowser {
            anchors.fill: parent
            active: MemoryService.browserOpen
        }
    }
}
