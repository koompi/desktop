import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

MouseArea {
    id: root
    property bool borderless: Config.options.bar.borderless

    readonly property bool running: TimerService.pomodoroRunning
    readonly property bool isBreak: TimerService.pomodoroBreak
    readonly property color phaseColor: running
        ? (isBreak ? Appearance.colors.colTertiary : Appearance.colors.colPrimary)
        : Appearance.colors.colOnLayer1Inactive
    readonly property string phaseIcon: !running ? "play_arrow" : (isBreak ? "local_cafe" : "local_fire_department")
    readonly property string timeText: {
        let m = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
        let s = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
        return `${m}:${s}`;
    }

    implicitWidth: rowLayout.implicitWidth + rowLayout.anchors.leftMargin + rowLayout.anchors.rightMargin
    implicitHeight: Appearance.sizes.barHeight
    hoverEnabled: !Config.options.bar.tooltips.clickToShow
    acceptedButtons: Qt.LeftButton | Qt.RightButton

    // Left-click: start/pause. Right-click: reset. (Documented in the popup.)
    onPressed: event => {
        if (event.button === Qt.LeftButton)
            TimerService.togglePomodoro();
        else if (event.button === Qt.RightButton)
            TimerService.resetPomodoro();
    }

    RowLayout {
        id: rowLayout
        spacing: 5
        anchors.fill: parent
        anchors.leftMargin: 4
        anchors.rightMargin: 4

        CircularProgress {
            Layout.alignment: Qt.AlignVCenter
            implicitSize: Math.round(Appearance.sizes.barHeight * 0.62)
            lineWidth: 2
            enableAnimation: false // value ticks several times a second; an 800ms ease would only lag
            value: TimerService.pomodoroLapDuration > 0 ? (TimerService.pomodoroSecondsLeft / TimerService.pomodoroLapDuration) : 0
            colPrimary: root.phaseColor

            MaterialSymbol {
                anchors.centerIn: parent
                text: root.phaseIcon
                iconSize: Appearance.font.pixelSize.small
                color: root.phaseColor
            }
        }

        StyledText {
            Layout.alignment: Qt.AlignVCenter
            font.pixelSize: Appearance.font.pixelSize.normal
            font.family: Appearance.font.family.monospace // tabular -> width stays constant as it ticks
            color: root.running ? Appearance.colors.colOnLayer1 : Appearance.colors.colOnLayer1Inactive
            text: root.timeText

            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
    }

    PomodoroPopup {
        hoverTarget: root
    }
}
