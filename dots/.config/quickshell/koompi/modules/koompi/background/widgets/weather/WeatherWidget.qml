import QtQuick
import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.modules.common.widgets.widgetCanvas
import qs.modules.koompi.background.widgets

AbstractBackgroundWidget {
    id: root

    configEntryName: "weather"

    implicitHeight: backgroundShape.implicitHeight
    implicitWidth: backgroundShape.implicitWidth

    StyledDropShadow {
        target: backgroundShape
    }

    MaterialShape {
        id: backgroundShape
        anchors.fill: parent
        shape: MaterialShape.Shape.Pill
        color: Appearance.colors.colPrimaryContainer
        implicitSize: 200

        StyledText {
            font {
                pixelSize: 80
                family: Appearance.font.family.expressive
                weight: Font.Medium
            }
            color: Appearance.colors.colPrimary
            // The service starts with temp: 0 (a number) and only stores the
            // "25°C" string after a successful fetch; (0).substring throws and
            // ?? cannot catch a throw.
            text: typeof Weather.data?.temp === "string" ? Weather.data.temp.substring(0, Weather.data.temp.length - 1) : "--°"
            anchors {
                right: parent.right
                top: parent.top
                rightMargin: 16
                topMargin: 20
            }
        }

        MaterialSymbol {
            iconSize: 80
            color: Appearance.colors.colOnPrimaryContainer
            text: Icons.getWeatherIcon(Weather.data.wCode) ?? "cloud"
            anchors {
                left: parent.left
                bottom: parent.bottom

                leftMargin: 16
                bottomMargin: 20
            }
        }
    }
}
