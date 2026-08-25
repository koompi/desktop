import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick

// What the idle layer shows and how it notices a hand: black, the KOOMPI mark
// drifting, a small clock. Kept apart from the layer-shell window so it can
// be hosted in any window, including a plain one for a headless capture.
Item {
    id: root

    // Something moved or was pressed: the host closes the layer.
    signal wake

    // A surface that appears under a stationary pointer gets a pointer-enter
    // from the compositor, which Qt hands over as a hover. Input only counts
    // once the content has been up this long, or the layer would dismiss
    // itself before its first frame.
    readonly property int armDelay: 500
    // A nudged desk is not a wake; a hand on the mouse is.
    readonly property int moveThreshold: 8
    // How often the mark takes a new place, and how long it takes to get
    // there. Both off the Appearance ladder on purpose: this is not UI motion,
    // it is the burn-in guard and it is meant to be barely noticed.
    readonly property int driftInterval: 20000
    readonly property int driftDuration: 4000
    // Neutral light grey on black, not a theme colour: the mark is the brand,
    // and the light scheme's on-background would vanish on this surface.
    readonly property color inkColor: "#9a9a9a"

    property bool armed: false
    property real anchorX: -1
    property real anchorY: -1

    focus: true

    function wakeIfArmed() {
        if (root.armed)
            root.wake();
    }

    Keys.onPressed: event => {
        root.wakeIfArmed();
        event.accepted = true;
    }

    Timer {
        interval: root.armDelay
        running: true
        onTriggered: root.armed = true
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.AllButtons
        cursorShape: Qt.BlankCursor
        onPositionChanged: mouse => {
            if (!root.armed) {
                // Whatever the pointer does before arming is the compositor
                // settling, and where it settles is the reference.
                root.anchorX = mouse.x;
                root.anchorY = mouse.y;
                return;
            }
            if (root.anchorX < 0 || Math.abs(mouse.x - root.anchorX) + Math.abs(mouse.y - root.anchorY) >= root.moveThreshold)
                root.wake();
        }
        onPressed: root.wakeIfArmed()
        onWheel: root.wakeIfArmed()
    }

    Item {
        id: scene
        anchors.fill: parent
        opacity: 0
        Component.onCompleted: fadeIn.start()

        NumberAnimation {
            id: fadeIn
            target: scene
            property: "opacity"
            to: 1
            duration: Appearance.animationDuration.slowest
            easing.type: Easing.OutCubic
        }

        CustomIcon {
            id: mark
            readonly property int size: Math.round(Math.min(root.width, root.height) * 0.18)
            width: size
            height: size
            x: Math.round((root.width - size) / 2)
            y: Math.round((root.height - size) / 2)
            source: "koompi-symbolic.svg"
            colorize: true
            color: root.inkColor

            Behavior on x {
                NumberAnimation {
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
            }
            Behavior on y {
                NumberAnimation {
                    duration: root.driftDuration
                    easing.type: Easing.InOutSine
                }
            }
        }

        // The burn-in guard: a new spot for the mark every driftInterval, kept
        // clear of the clock's corner.
        Timer {
            interval: root.driftInterval
            running: true
            repeat: true
            onTriggered: {
                const maxX = Math.max(0, root.width - mark.size);
                const maxY = Math.max(0, root.height - mark.size - clock.height - clock.anchors.margins);
                mark.x = Math.round(Math.random() * maxX);
                mark.y = Math.round(Math.random() * maxY);
            }
        }

        StyledText {
            id: clock
            anchors {
                right: parent.right
                bottom: parent.bottom
                margins: 32
            }
            text: DateTime.time
            color: root.inkColor
            font.pixelSize: Appearance.font.pixelSize.huge
            font.family: Appearance.font.family.numbers
        }
    }
}
