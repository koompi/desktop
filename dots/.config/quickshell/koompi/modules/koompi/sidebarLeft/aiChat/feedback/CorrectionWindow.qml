import qs.modules.common
import qs.modules.koompi.sidebarLeft.aiChat.feedback
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * The correction modal as a window, so "This is wrong" reaches it from a
 * citation row inside a panel that cannot host an overlay of its own.
 */
PanelWindow {
    id: window

    required property var service

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
    WlrLayershell.namespace: "quickshell:aiCorrection"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
        anchors.fill: parent
        onClicked: event => {
            const local = dialog.mapFromItem(null, event.x, event.y);
            if (local.x < 0 || local.y < 0 || local.x > dialog.width || local.y > dialog.height) window.service.closeCorrection();
        }
    }

    CorrectionDialog {
        id: dialog
        anchors.centerIn: parent
        width: Math.min(560, window.width - Appearance.sizes.elevationMargin * 8)

        target: window.service.pendingCorrection
        focus: true
        onClosed: window.service.closeCorrection()
        Keys.onEscapePressed: window.service.closeCorrection()
        Component.onCompleted: focusInput()
    }
}
