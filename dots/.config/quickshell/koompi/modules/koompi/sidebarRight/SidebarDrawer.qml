import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarRight.quickToggles.classicStyle
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string title
    property alias sourceComponent: body.sourceComponent
    property bool shown: false
    signal dismissed

    width: parent?.width ?? 0
    height: parent?.height ?? 0
    x: shown ? 0 : width
    visible: x < width
    color: Appearance.colors.colLayer0
    radius: parent?.radius ?? 0

    Behavior on x {
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    MouseArea {
        anchors.fill: parent
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.spacing.normal
        spacing: Appearance.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.normal

            QuickToggleButton {
                buttonIcon: "arrow_back"
                onClicked: root.dismissed()
            }
            StyledText {
                Layout.fillWidth: true
                elide: Text.ElideRight
                font.pixelSize: Appearance.font.pixelSize.larger
                color: Appearance.colors.colOnLayer0
                text: root.title
            }
        }

        Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            clip: true

            Loader {
                id: body
                anchors.fill: parent
                active: root.visible
            }
        }
    }
}
