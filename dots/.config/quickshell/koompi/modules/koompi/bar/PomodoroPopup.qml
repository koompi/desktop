import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

StyledPopup {
    id: root
    property bool isBreak: TimerService.pomodoroBreak
    property bool isLongBreak: TimerService.pomodoroLongBreak

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 4

        StyledPopupHeaderRow {
            icon: root.isBreak ? "local_cafe" : "local_fire_department"
            label: root.isLongBreak ? Translation.tr("Long break") : root.isBreak ? Translation.tr("Break") : Translation.tr("Focus")
        }

        StyledPopupValueRow {
            icon: "timer"
            label: Translation.tr("Time left:")
            value: {
                let m = Math.floor(TimerService.pomodoroSecondsLeft / 60).toString().padStart(2, '0');
                let s = Math.floor(TimerService.pomodoroSecondsLeft % 60).toString().padStart(2, '0');
                return `${m}:${s}`;
            }
        }

        StyledPopupValueRow {
            icon: "repeat"
            label: Translation.tr("Cycle:")
            value: `${TimerService.pomodoroCycle + 1} / ${TimerService.cyclesBeforeLongBreak}`
        }

        StyledPopupValueRow {
            icon: TimerService.pomodoroRunning ? "play_arrow" : "pause"
            label: Translation.tr("Status:")
            value: TimerService.pomodoroRunning ? Translation.tr("Running") : Translation.tr("Paused")
        }

        StyledText {
            Layout.topMargin: 2
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignLeft
            wrapMode: Text.Wrap
            color: Appearance.colors.colSubtext
            font.pixelSize: Appearance.font.pixelSize.small
            text: Translation.tr("Click: start/pause · Right-click: reset")
        }
    }
}
