import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

Rectangle {
    id: root
    property string title
    property alias sourceComponent: body.sourceComponent
    property bool shown: false
    signal dismissed

    property real dragX: 0

    width: parent?.width ?? 0
    height: parent?.height ?? 0
    x: (shown ? 0 : width) + dragX
    visible: x < width
    color: Appearance.colors.colLayer0
    radius: parent?.radius ?? 0

    Behavior on x {
        enabled: !dragHandler.active
        animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
    }

    // Drag right to go back. A handler, not a MouseArea, so it only takes the
    // grab once the pointer has travelled: taps still reach the toggles.
    DragHandler {
        id: dragHandler
        target: null
        yAxis.enabled: false
        onActiveTranslationChanged: root.dragX = Math.max(0, activeTranslation.x)
        onActiveChanged: {
            if (active) {
                root.dragX = 0;
                return;
            }
            if (root.dragX > root.width / 4) root.dismissed();
            root.dragX = 0;
        }
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
            Layout.fillHeight: false
            spacing: Appearance.spacing.normal

            RippleButton {
                implicitWidth: 32
                implicitHeight: 32
                buttonRadius: 16
                onClicked: root.dismissed()
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    iconSize: 20
                    color: Appearance.colors.colOnLayer0
                    text: "arrow_back"
                }
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

    // Topmost, but deaf to every other button, so it costs the content nothing.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.BackButton
        onClicked: root.dismissed()
    }
}
