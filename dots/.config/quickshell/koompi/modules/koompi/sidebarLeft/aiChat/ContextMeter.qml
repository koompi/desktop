import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Token HUD (#14): a thin context-fill bar, and a warning once it is nearly full.
ColumnLayout {
    id: root
    visible: Ai.tokenCount.total > 0
    spacing: 4

    Rectangle {
        Layout.fillWidth: true
        height: 3
        radius: Appearance.rounding.full
        color: Appearance.colors.colLayer1
        Rectangle {
            readonly property real fill: Ai.tokenCount.total / Math.max(1, Ai.contextWindow)
            width: parent.width * Math.min(1.0, fill)
            height: parent.height
            radius: parent.radius
            color: fill >= 0.85 ? Appearance.colors.colError
                 : fill >= 0.60 ? Appearance.m3colors.m3tertiary
                 : Appearance.colors.colPrimary
            Behavior on width {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }
        }
        MouseArea {
            id: contextBarMouseArea
            anchors.fill: parent
            anchors.topMargin: -4
            anchors.bottomMargin: -4
            hoverEnabled: true
            acceptedButtons: Qt.NoButton

            StyledToolTip {
                extraVisibleCondition: false
                alternativeVisibleCondition: contextBarMouseArea.containsMouse
                text: Translation.tr("Context: %1 / %2 tokens\nInput: %3 — Output: %4").arg(Ai.tokenCount.total).arg(Ai.contextWindow).arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
            }
        }
    }
    StyledText {
        visible: Ai.tokenCount.total >= Ai.contextWindow * 0.90
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        font.pixelSize: Appearance.font.pixelSize.small
        font.italic: true
        color: Appearance.colors.colError
        text: Translation.tr("Context nearly full — will compact soon")
    }
}
