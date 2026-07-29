import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import Quickshell
import Quickshell.Widgets

Item {
    id: root

    property var entry
    property real iconSize: 64
    property bool selected: false
    property bool launching: false
    property bool dimmed: false

    signal activated
    signal hovered

    opacity: root.dimmed ? 0.35 : 1
    Behavior on opacity {
        NumberAnimation {
            duration: Appearance.animation.elementMoveFast.duration
            easing.type: Easing.BezierSpline
            easing.bezierCurve: Appearance.animationCurves.expressiveEffects
        }
    }

    Rectangle {
        anchors.fill: parent
        anchors.margins: 6
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1Hover
        opacity: root.selected ? 1 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animationCurves.expressiveEffects
            }
        }
    }

    Column {
        anchors.centerIn: parent
        spacing: 8

        Item {
            anchors.horizontalCenter: parent.horizontalCenter
            implicitWidth: root.iconSize
            implicitHeight: root.iconSize

            IconImage {
                id: appIcon
                anchors.fill: parent
                source: Quickshell.iconPath(root.entry?.icon ?? "", "image-missing")
                // Shrinks under the spinner rather than hiding, so the tile
                // still says which app is starting.
                scale: root.launching ? 0.62 : (mouseArea.pressed ? 0.92 : 1)
                opacity: root.launching ? 0.55 : 1

                Behavior on scale {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                    }
                }
                Behavior on opacity {
                    NumberAnimation {
                        duration: Appearance.animation.elementMoveFast.duration
                        easing.type: Easing.BezierSpline
                        easing.bezierCurve: Appearance.animationCurves.expressiveEffects
                    }
                }
            }

            Loader {
                anchors.centerIn: parent
                active: root.launching
                sourceComponent: MaterialLoadingIndicator {
                    implicitSize: root.iconSize
                    loading: true
                }
            }
        }

        StyledText {
            width: root.width - 12
            horizontalAlignment: Text.AlignHCenter
            text: root.entry?.name ?? ""
            elide: Text.ElideRight
            maximumLineCount: 1
            color: Appearance.colors.colOnLayer0
            font.pixelSize: Appearance.font.pixelSize.smaller
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onEntered: root.hovered()
        onClicked: root.activated()
    }
}
