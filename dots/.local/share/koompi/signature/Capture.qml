import QtQuick
import QtQuick.Window
import QtMultimedia

Window {
    id: root
    width: 960; height: 660
    visible: true
    title: "Capture signature"
    color: "#100e0e"

    property int deviceIndex: 0
    property bool busy: false

    readonly property color accent: "#dac0c9"
    readonly property color fg: "#e8e1e1"
    readonly property color dim: "#958f90"

    MediaDevices { id: devices }

    CaptureSession {
        camera: Camera {
            id: cam
            cameraDevice: devices.videoInputs.length > root.deviceIndex
                          ? devices.videoInputs[root.deviceIndex] : devices.defaultVideoInput
            active: true
        }
        imageCapture: ImageCapture {
            id: shot
            onImageSaved: Qt.exit(0)
            onErrorOccurred: Qt.exit(3)
        }
        videoOutput: view
    }

    VideoOutput {
        id: view
        anchors.fill: parent
        anchors.bottomMargin: 96
        fillMode: VideoOutput.PreserveAspectFit
        transform: Scale { origin.x: view.width / 2; xScale: -1 }
    }

    Item {
        id: guide
        anchors.centerIn: view
        width: view.width * 0.78
        height: view.height * 0.42

        Rectangle {
            anchors.fill: parent
            color: "transparent"
            border.color: root.accent
            border.width: 2
            radius: 6
        }
        Repeater {
            model: [[0,0],[1,0],[0,1],[1,1]]
            Rectangle {
                width: 22; height: 3; color: root.accent
                x: modelData[0] ? parent.width - width : 0
                y: modelData[1] ? parent.height - height : 0
            }
        }
    }

    Component {
        id: plate
        Rectangle {
            property alias text: label.text
            property int fontSize: 17
            property color tone: root.fg
            width: label.width + 26; height: label.height + 14
            radius: height / 2
            color: Qt.rgba(0, 0, 0, 0.62)
            Text {
                id: label
                anchors.centerIn: parent
                color: tone; font.pixelSize: fontSize
            }
        }
    }

    Loader {
        sourceComponent: plate
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: guide.top
        anchors.bottomMargin: 18
        onLoaded: item.text = "sign a white sheet, fill the box, keep it flat and evenly lit"
    }

    Loader {
        sourceComponent: plate
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: guide.bottom
        anchors.topMargin: 14
        onLoaded: {
            item.text = "avoid glare and hard shadows across the paper"
            item.fontSize = 14
        }
    }

    Row {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 26
        spacing: 14

        Rectangle {
            width: 168; height: 46; radius: 23
            color: root.busy ? "#4a4647" : root.accent
            Text {
                anchors.centerIn: parent
                text: root.busy ? "saving..." : "Capture"
                color: "#221f20"; font.pixelSize: 16; font.bold: true
            }
            MouseArea { anchors.fill: parent; onClicked: root.take() }
        }

        Rectangle {
            width: 130; height: 46; radius: 23
            color: "transparent"
            border.color: root.dim; border.width: 1
            visible: devices.videoInputs.length > 1
            Text {
                anchors.centerIn: parent; text: "Switch lens"
                color: root.fg; font.pixelSize: 15
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.deviceIndex = (root.deviceIndex + 1) % devices.videoInputs.length
            }
        }

        Rectangle {
            width: 110; height: 46; radius: 23
            color: "transparent"
            border.color: root.dim; border.width: 1
            Text { anchors.centerIn: parent; text: "Cancel"; color: root.fg; font.pixelSize: 15 }
            MouseArea { anchors.fill: parent; onClicked: Qt.exit(1) }
        }
    }

    function take() {
        if (busy)
            return
        busy = true
        shot.captureToFile("/tmp/koompi-sig-raw.jpg")
    }

    Item {
        focus: true
        Keys.onEscapePressed: Qt.exit(1)
        Keys.onReturnPressed: root.take()
        Keys.onSpacePressed: root.take()
    }
}
