import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * "I've been getting things wrong." (36:163-182)
 *
 * Stated grounding against measured accuracy, over a window. The gap is only
 * drawn when there is enough behind it to mean anything; until then the card
 * shows the counts and says what is still missing rather than inventing a
 * number for the sake of a bar.
 */
Rectangle {
    id: root

    readonly property var report: Ai.trustReport
    readonly property bool enough: root.report.enough
    readonly property bool overconfident: root.report.overconfident
    readonly property real stated: root.report.statedGrounding ?? 0
    readonly property real measured: root.report.measuredAccuracy ?? 0

    implicitHeight: layout.implicitHeight + Appearance.spacing.normal * 2
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: root.overconfident ? Appearance.colors.colError : Appearance.colors.colOutlineVariant

    component Meter: ColumnLayout {
        id: meter
        required property string label
        required property real value
        required property color barColor
        spacing: Appearance.spacing.small

        RowLayout {
            Layout.fillWidth: true

            StyledText {
                Layout.fillWidth: true
                text: meter.label
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: meter.barColor
            }

            StyledText {
                text: `${Math.round(meter.value * 100)}%`
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.monospace
                color: meter.barColor
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 7
            radius: Appearance.rounding.full
            color: Appearance.colors.colSurfaceContainerHighest

            Rectangle {
                width: parent.width * Math.max(0, Math.min(1, meter.value))
                height: parent.height
                radius: parent.radius
                color: meter.barColor

                Behavior on width {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
            }
        }
    }

    ColumnLayout {
        id: layout
        anchors {
            fill: parent
            margins: Appearance.spacing.normal
        }
        spacing: Appearance.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            MaterialSymbol {
                text: root.overconfident ? "warning" : "monitoring"
                iconSize: Appearance.font.pixelSize.large
                color: root.overconfident ? Appearance.colors.colError : Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                text: root.overconfident
                    ? Translation.tr("I've been getting things wrong")
                    : Translation.tr("How well I've been doing")
                font.pixelSize: Appearance.font.pixelSize.normal
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                wrapMode: Text.Wrap
            }

            Rectangle {
                implicitWidth: countLabel.implicitWidth + Appearance.spacing.normal
                implicitHeight: countLabel.implicitHeight + Appearance.spacing.hairline * 2
                radius: Appearance.rounding.full
                color: Appearance.colors.colErrorContainer

                StyledText {
                    id: countLabel
                    anchors.centerIn: parent
                    text: Translation.tr("%1 corrections in %2 days").arg(root.report.corrections).arg(root.report.windowDays)
                    font.pixelSize: Appearance.font.pixelSize.smallest
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnErrorContainer
                }
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("Across the answers that carried sources: what I claimed as grounding, against how often you had to correct me.")
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        Meter {
            Layout.fillWidth: true
            visible: root.report.groundedTurns > 0
            label: Translation.tr("Stated grounding")
            value: root.stated
            barColor: Appearance.colors.colPrimary
        }

        Meter {
            Layout.fillWidth: true
            visible: root.report.groundedTurns > 0
            label: Translation.tr("Not corrected")
            value: root.measured
            barColor: Appearance.colors.colError
        }

        // The honest branch: a gap is only named when the window holds enough
        // to compute one. Otherwise the counts stand alone and say so.
        StyledText {
            Layout.fillWidth: true
            text: root.enough
                ? (root.overconfident
                    ? Translation.tr("I'm %1 points overconfident. Recalibrating makes me say when an answer is not backed.")
                        .arg(Math.round((root.report.gap ?? 0) * 100))
                    : Translation.tr("I claim %1 points less grounding than my corrected record shows, so there is nothing to recalibrate away. Only answers you told me were wrong count against me here.")
                        .arg(Math.abs(Math.round((root.report.gap ?? 0) * 100))))
                : Translation.tr("Not enough yet to say whether that gap is real: %1 of %2 grounded answers, %3 of %4 corrections. Until both are met the two bars are counts, not a comparison.")
                    .arg(root.report.groundedTurns).arg(root.report.minTurns)
                    .arg(root.report.corrections).arg(root.report.minCorrections)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.overconfident ? Appearance.colors.colError : Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        StyledText {
            Layout.fillWidth: true
            text: [
                Translation.tr("%1 answers seen").arg(root.report.turns),
                Translation.tr("%1 with sources").arg(root.report.groundedTurns),
                Translation.tr("%1 fixed without being asked").arg(root.report.autoRepairs)
            ].join("  ·  ")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.family: Appearance.font.family.monospace
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            DialogButton {
                buttonText: Translation.tr("Recalibrate · say so below 85%")
                colText: root.overconfident ? Appearance.colors.colError : Appearance.colors.colSubtext
                onClicked: Ai.recalibrate()
                StyledToolTip {
                    text: Translation.tr("Stores a standing instruction to say plainly when an answer is not backed by a source.")
                }
            }

            DialogButton {
                buttonText: Ai.recallPaused
                    ? Translation.tr("Resume recalled memories")
                    : Translation.tr("Pause recalled memories 7 days")
                onClicked: {
                    if (Ai.recallPaused) Ai.resumeRecall();
                    else Ai.pauseRecall(7);
                }
                StyledToolTip {
                    text: Translation.tr("Stops memories being read into the prompt. Nothing is deleted.")
                }
            }
        }
    }
}
