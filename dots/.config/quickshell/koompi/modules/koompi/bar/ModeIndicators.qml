import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets

/**
 * Modes that outlive whatever switched them on: keep awake, night light and
 * Kiri dictation. Each light shows only while its mode is active and a click
 * turns the mode off, so the bar is both the reminder and the switch.
 */
RowLayout {
    id: root

    property real realSpacing: Appearance.spacing.large
    property color color: Appearance.colors.colOnLayer0
    readonly property var tooltipEdges: (!Config.options.bar.bottom && !Config.options.bar.vertical) ? Edges.Bottom : Edges.Top

    // Kiri marks a running dictation with $XDG_RUNTIME_DIR/kiri-voice.pid
    // (kiri/src/ui/voice.rs, voice_pid_path). The file outlives a crash, so the
    // pid is checked against /proc before the light goes on. Same 2s poll as
    // ScreenRecording, and paused while locked for the same reason.
    property bool dictating: false

    spacing: 0

    Process {
        id: kiriCheck
        command: ["bash", "-c", "read -r pid < \"${XDG_RUNTIME_DIR:-/tmp}/kiri-voice.pid\" && [[ -d /proc/$pid ]]"]
        onExited: exitCode => root.dictating = (exitCode === 0)
    }

    Timer {
        running: PowerSaving.awake
        repeat: true
        interval: PowerSaving.interval(2000)
        triggeredOnStart: true
        onTriggered: if (!kiriCheck.running)
            kiriCheck.running = true
    }

    component ModeIndicator: Revealer {
        id: indicator
        required property string icon
        required property string tooltip
        required property var toggle
        property color iconColor: root.color

        Layout.fillHeight: true
        Layout.rightMargin: reveal ? root.realSpacing : 0
        Behavior on Layout.rightMargin {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }

        MaterialSymbol {
            text: indicator.icon
            iconSize: Appearance.font.pixelSize.larger
            color: indicator.iconColor

            MouseArea {
                id: indicatorHover
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: indicator.toggle()
            }
            PopupToolTip {
                extraVisibleCondition: indicatorHover.containsMouse
                anchorEdges: root.tooltipEdges
                text: indicator.tooltip
            }
        }
    }

    ModeIndicator {
        reveal: Idle.inhibit
        icon: "coffee"
        tooltip: Translation.tr("Keep awake is on. Click to turn it off")
        toggle: () => Idle.toggleInhibit()
    }
    ModeIndicator {
        reveal: Hyprsunset.temperatureActive
        icon: "bedtime"
        tooltip: Translation.tr("Night light is on. Click to turn it off")
        toggle: () => Hyprsunset.toggleTemperature()
    }
    ModeIndicator {
        reveal: root.dictating
        icon: "mic"
        // A live microphone is a recording; same colour as the recording light.
        iconColor: Appearance.m3colors.m3error
        tooltip: Translation.tr("Kiri is listening. Click to stop and paste")
        // What the hotkey does when pressed again: stop, transcribe, paste.
        toggle: () => Quickshell.execDetached(["kiri", "voice"])
    }
}
