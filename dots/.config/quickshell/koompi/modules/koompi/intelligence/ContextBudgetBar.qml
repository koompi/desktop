import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.koompi.intelligence
import QtQuick
import QtQuick.Layouts

// The budget against the window the model will actually accept, not the number
// in the config file. Above the compaction threshold the fill turns to the
// error colour, because that is where the turn starts costing history.
Item {
    id: root

    property bool compact: false
    readonly property int tokens: IntelligenceContext.contextTokens
    readonly property int window: IntelligenceContext.contextWindow
    readonly property real fraction: IntelligenceContext.contextFraction
    readonly property bool overThreshold: root.window > 0 && root.tokens > IntelligenceContext.contextWindow * 0.6

    implicitHeight: column.implicitHeight
    visible: root.window > 0

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: Appearance.spacing.hairline

        StyledText {
            visible: !root.compact
            Layout.fillWidth: true
            text: Translation.tr("Context")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            font.letterSpacing: 1
            color: Appearance.colors.colSubtext
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 6
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer2

            Rectangle {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: parent.width * root.fraction
                radius: Appearance.rounding.full
                color: root.overThreshold ? Appearance.colors.colError : Appearance.colors.colPrimary

                Behavior on width {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
            }
        }

        StyledText {
            visible: !root.compact
            Layout.fillWidth: true
            text: Translation.tr("%1 / %2 tokens").arg(root.tokens).arg(root.window)
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: root.overThreshold ? Appearance.colors.colError : Appearance.colors.colSubtext
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: barHover
        anchors.fill: parent
        hoverEnabled: true
    }

    StyledToolTip {
        text: Translation.tr("%1 of the model's %2-token window").arg(root.tokens).arg(root.window)
        extraVisibleCondition: barHover.containsMouse
    }
}
