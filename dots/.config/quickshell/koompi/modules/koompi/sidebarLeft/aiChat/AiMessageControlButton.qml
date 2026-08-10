import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick

GroupButton {
    id: button
    property string buttonIcon
    property bool activated: false
    property string accessibleName: ""
    Accessible.role: Accessible.Button
    Accessible.name: accessibleName
    toggled: activated
    baseWidth: height
    colBackgroundHover: Appearance.colors.colSecondaryContainerHover
    colBackgroundActive: Appearance.colors.colSecondaryContainerActive

    // Tab reaches it, Space and Return fire it, and the ring says where you are.
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true
    Keys.onPressed: event => {
        if (event.key === Qt.Key_Space || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            button.clicked()
            event.accepted = true
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: button.buttonRadius
        color: "transparent"
        border.width: button.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    contentItem: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        iconSize: Appearance.font.pixelSize.larger
        text: buttonIcon
        color: button.activated ? Appearance.m3colors.m3onPrimary :
            button.enabled ? Appearance.m3colors.m3onSurface :
            Appearance.colors.colOnLayer1Inactive

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }
}
