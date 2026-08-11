import qs.modules.common
import qs.modules.koompi.sidebarLeft.aiChat.approval
import qs.services
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland

/**
 * The rule list as a window of its own, because the approval card lives in a
 * 500 px column and a list you have to squint at is not a way to revoke trust.
 */
PanelWindow {
    id: window

    signal dismissed()

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
    WlrLayershell.namespace: "quickshell:approvalRules"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
        anchors.fill: parent
        onClicked: window.dismissed()
    }

    Rectangle {
        anchors.centerIn: parent
        implicitWidth: Math.min(560, window.width - Appearance.sizes.elevationMargin * 8)
        implicitHeight: Math.min(520, window.height - Appearance.sizes.elevationMargin * 8)
        radius: Appearance.rounding.large
        color: Appearance.m3colors.m3surfaceContainerHigh

        focus: true
        Keys.onEscapePressed: window.dismissed()

        MouseArea { // the card swallows its own clicks
            anchors.fill: parent
        }

        ApprovalRulesList {
            id: rules
            anchors.fill: parent
            anchors.margins: Appearance.spacing.large
            onDismissed: window.dismissed()
        }
    }
}
