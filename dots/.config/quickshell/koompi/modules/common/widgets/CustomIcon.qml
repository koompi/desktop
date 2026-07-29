import QtQuick
import Quickshell
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects

Item {
    id: root

    property bool colorize: false
    property color color
    property string source: ""
    property string iconFolder: Qt.resolvedUrl(Quickshell.shellPath("assets/icons"))  // The folder to check first
    width: 30
    height: 30

    Image {
        id: iconImage
        anchors.fill: parent
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
        sourceSize.width: Math.ceil(Math.min(root.width, root.height) * 2)
        sourceSize.height: Math.ceil(Math.min(root.width, root.height) * 2)
        source: {
            const fullPathWhenSourceIsIconName = iconFolder + "/" + root.source;
            if (iconFolder && fullPathWhenSourceIsIconName) {
                return fullPathWhenSourceIsIconName
            }
            return root.source
        }
    }

    Loader {
        active: root.colorize
        anchors.fill: iconImage
        sourceComponent: ColorOverlay {
            source: iconImage
            color: root.color
        }
    }
}
