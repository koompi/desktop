import QtQuick
import QtQuick.Window

Window {
    id: root
    width: 900; height: 600
    visible: true
    title: "Signature preview"
    color: "#100e0e"

    readonly property color accent: "#dac0c9"
    readonly property color fg: "#e8e1e1"
    readonly property color dim: "#958f90"
    readonly property string src: "file:///tmp/koompi-sig-preview.png"

    Text {
        id: heading
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: 22
        text: "this is what gets stamped on the page"
        color: root.fg; font.pixelSize: 17
    }

    Row {
        id: panes
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: heading.bottom
        anchors.topMargin: 20
        spacing: 18

        Repeater {
            model: [
                { bg: "#ffffff", label: "on white paper" },
                { bg: "#1b1b1b", label: "on a dark page" }
            ]
            Column {
                spacing: 8
                Rectangle {
                    width: 400; height: 300
                    color: modelData.bg
                    radius: 8
                    Image {
                        anchors.fill: parent
                        anchors.margins: 18
                        source: root.src
                        fillMode: Image.PreserveAspectFit
                        smooth: true
                        cache: false
                    }
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: modelData.label; color: root.dim; font.pixelSize: 13
                }
            }
        }
    }

    Text {
        id: hint
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: panes.bottom
        anchors.topMargin: 18
        text: "strokes broken up? use Bolder.   speckled background? use Cleaner."
        color: root.dim; font.pixelSize: 13
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 24
        spacing: 12

        Rectangle {
            width: 150; height: 44; radius: 22; color: root.accent
            Text {
                anchors.centerIn: parent; text: "Save"
                color: "#221f20"; font.pixelSize: 16; font.bold: true
            }
            MouseArea { anchors.fill: parent; onClicked: Qt.exit(0) }
        }
        Repeater {
            model: [
                { t: "Bolder", code: 3 },
                { t: "Cleaner", code: 4 },
                { t: "Retake", code: 2 },
                { t: "Cancel", code: 1 }
            ]
            Rectangle {
                width: 106; height: 44; radius: 22
                color: "transparent"
                border.color: root.dim; border.width: 1
                Text { anchors.centerIn: parent; text: modelData.t; color: root.fg; font.pixelSize: 15 }
                MouseArea { anchors.fill: parent; onClicked: Qt.exit(modelData.code) }
            }
        }
    }

    Item {
        focus: true
        Keys.onEscapePressed: Qt.exit(1)
        Keys.onReturnPressed: Qt.exit(0)
    }
}
