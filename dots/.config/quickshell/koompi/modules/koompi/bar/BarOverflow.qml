import qs.modules.koompi.bar.weather
import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

MouseArea { // One trigger for the status services that do not earn permanent bar space
    id: root

    // Weather, media, the utility actions and an idle pomodoro are all occasional.
    // Each used to hold its own slot in the bar; together they crowded out the
    // things that are always relevant. They live behind this single control now.
    implicitWidth: Appearance.sizes.baseBarHeight
    implicitHeight: Appearance.sizes.baseBarHeight
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton

    MaterialSymbol {
        anchors.centerIn: parent
        text: "more_horiz"
        iconSize: Appearance.font.pixelSize.larger
        color: root.containsMouse ? Appearance.colors.colOnLayer0 : Appearance.colors.colOnLayer1Inactive

        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
    }

    StyledPopup {
        hoverTarget: root

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 6

            StyledPopupHeaderRow {
                icon: "more_horiz"
                label: Translation.tr("More")
            }

            UtilButtons {
                Layout.alignment: Qt.AlignHCenter
            }

            Pomodoro {
                Layout.alignment: Qt.AlignHCenter
                // Already inside a popup; a second popup window would nest.
                detailPopup: false
            }

            Loader {
                Layout.alignment: Qt.AlignHCenter
                active: Config.options.bar.weather.enable
                sourceComponent: WeatherBar {}
            }

            Media {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: 260
                visible: MprisController.hasActiveMedia
            }
        }
    }
}
