pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.background.widgets.clock
import QtQuick
import QtQuick.Layouts

/**
 * Clock, date and lock indicator for the lock surface.
 *
 * The desktop clock lives in a WlrLayer.Bottom panel the compositor hides while
 * the session is locked, so the lock screen draws its own. Face and indicator
 * still follow the same configuration keys, so the two read as one clock.
 */
Item {
    id: root

    // Contrast colour for anything drawn straight onto the scrimmed wallpaper.
    required property color colText

    readonly property string clockStyle: Config.options.background.widgets.clock.styleLocked
    readonly property bool showQuote: Config.options.background.widgets.clock.quote.enable
        && Config.options.background.widgets.clock.quote.text.length > 0

    implicitWidth: contentColumn.implicitWidth
    implicitHeight: contentColumn.implicitHeight

    Column {
        id: contentColumn
        anchors.centerIn: parent
        spacing: 12

        Loader {
            id: cookieLoader
            anchors.horizontalCenter: parent.horizontalCenter
            active: root.clockStyle === "cookie"
            visible: active
            sourceComponent: Column {
                spacing: 10
                CookieClock {
                    anchors.horizontalCenter: parent.horizontalCenter
                }
                Loader {
                    anchors.horizontalCenter: parent.horizontalCenter
                    active: root.showQuote
                    visible: active
                    sourceComponent: CookieQuote {}
                }
            }
        }

        Loader {
            id: digitalLoader
            anchors.horizontalCenter: parent.horizontalCenter
            active: root.clockStyle !== "cookie"
            visible: active
            sourceComponent: DigitalClock {
                colText: root.colText
                textHorizontalAlignment: Text.AlignHCenter
            }
        }

        // Lock indicator. Carries its own container on the cookie face because
        // that face is a solid shape the text would otherwise float beside.
        Loader {
            anchors.horizontalCenter: parent.horizontalCenter
            active: Config.options.lock.showLockedText
            visible: active
            sourceComponent: Rectangle {
                implicitWidth: indicatorRow.implicitWidth + 12 * 2
                implicitHeight: indicatorRow.implicitHeight + 6 * 2
                radius: Appearance.rounding.small
                color: root.clockStyle === "cookie"
                    ? Appearance.colors.colSecondaryContainer
                    : "transparent"

                RowLayout {
                    id: indicatorRow
                    anchors.centerIn: parent
                    spacing: 6

                    readonly property color colContent: root.clockStyle === "cookie"
                        ? Appearance.colors.colOnSecondaryContainer
                        : root.colText

                    MaterialSymbol {
                        Layout.alignment: Qt.AlignVCenter
                        text: "lock"
                        fill: 1
                        iconSize: Appearance.font.pixelSize.huge
                        color: indicatorRow.colContent
                        style: Text.Raised
                        styleColor: Appearance.colors.colShadow
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignVCenter
                        text: Translation.tr("Locked")
                        color: indicatorRow.colContent
                        font.pixelSize: Appearance.font.pixelSize.large
                        style: Text.Raised
                        styleColor: Appearance.colors.colShadow
                    }
                }
            }
        }
    }
}
