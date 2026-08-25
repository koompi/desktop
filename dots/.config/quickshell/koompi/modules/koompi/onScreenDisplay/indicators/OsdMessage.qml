import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// koompi-osd's line: OsdValueIndicator's pill, sized to its text, bar optional
Item {
    id: root
    property string icon: ""
    property string message: ""
    property real progress: -1 // 0..1 draws the bar; anything below draws none

    implicitWidth: pill.implicitWidth + 2 * Appearance.sizes.elevationMargin
    implicitHeight: pill.implicitHeight + 2 * Appearance.sizes.elevationMargin

    StyledRectangularShadow {
        target: pill
    }
    Rectangle {
        id: pill
        property real padding: 10
        anchors {
            fill: parent
            margins: Appearance.sizes.elevationMargin
        }
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer0
        implicitWidth: Math.max(Appearance.sizes.osdWidth, row.implicitWidth + 2 * padding)
        implicitHeight: row.implicitHeight + 2 * padding

        RowLayout {
            id: row
            anchors.centerIn: parent
            spacing: 10

            MaterialSymbol {
                visible: root.icon !== ""
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: 10
                color: Appearance.colors.colOnLayer0
                iconSize: Appearance.font.pixelSize.hugeass
                text: root.icon
            }
            ColumnLayout {
                Layout.alignment: Qt.AlignVCenter
                Layout.leftMargin: root.icon === "" ? 20 : 0
                Layout.rightMargin: 20
                spacing: 5

                RowLayout {
                    StyledText {
                        visible: root.message !== ""
                        Layout.fillWidth: true
                        Layout.maximumWidth: Appearance.sizes.osdWidth * 3
                        color: Appearance.colors.colOnLayer0
                        wrapMode: Text.Wrap
                        text: root.message
                    }
                    StyledText {
                        visible: root.progress >= 0
                        color: Appearance.colors.colOnLayer0
                        font.pixelSize: Appearance.font.pixelSize.small
                        text: Math.round(root.progress * 100)
                    }
                }
                StyledProgressBar {
                    visible: root.progress >= 0
                    Layout.fillWidth: true
                    value: Math.max(0, root.progress)
                }
            }
        }
    }
}
