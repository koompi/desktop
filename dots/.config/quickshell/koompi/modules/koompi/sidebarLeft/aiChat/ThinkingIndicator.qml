import qs.services
import qs.modules.common
import QtQuick

// The model thinking, not the system working. Non-directional on purpose: a
// travelling bar would promise a finish the model cannot promise, and it stops
// the instant the first token lands, so the user always knows which of the two
// is happening.
Item {
    id: root
    property bool active: true
    property real dotSize: 5

    implicitWidth: dots.implicitWidth
    implicitHeight: root.dotSize * 2

    Accessible.role: Accessible.Indicator
    Accessible.name: Translation.tr("The model is thinking")

    Row {
        id: dots
        anchors.centerIn: parent
        spacing: root.dotSize

        Repeater {
            model: 3

            Rectangle {
                id: dot
                required property int index
                width: root.dotSize
                height: root.dotSize
                radius: width / 2
                color: Appearance.colors.colPrimary
                opacity: 0.25

                SequentialAnimation on opacity {
                    running: root.active
                    loops: Animation.Infinite
                    PauseAnimation { duration: dot.index * Appearance.animationDuration.snap }
                    NumberAnimation {
                        to: 1
                        duration: Appearance.animationDuration.deliberate
                        easing.type: Easing.InOutSine
                    }
                    NumberAnimation {
                        to: 0.25
                        duration: Appearance.animationDuration.deliberate
                        easing.type: Easing.InOutSine
                    }
                    PauseAnimation { duration: (2 - dot.index) * Appearance.animationDuration.snap }
                }
            }
        }
    }
}
