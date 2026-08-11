pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft.aiChat.activity
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * The agent while it works: what it was asked, how long it has had, what it has
 * done so far, and a cancel that reaches the process. Collapses to nothing when
 * no run is in flight - the finished run belongs to the transcript, not here.
 */
Item {
    id: root

    readonly property bool active: AgentRun.running || AgentRun.cancelling
    readonly property int elapsedSeconds: Math.floor(AgentRun.elapsedMs / 1000)

    function clock(seconds: int): string {
        return `${Math.floor(seconds / 60)}:${String(seconds % 60).padStart(2, "0")}`;
    }

    implicitHeight: root.active ? card.implicitHeight : 0
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    Rectangle {
        id: card
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        implicitHeight: layout.implicitHeight + Appearance.spacing.normal * 2
        radius: Appearance.rounding.small
        color: Appearance.colors.colLayer2

        ColumnLayout {
            id: layout
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Appearance.spacing.normal
            spacing: Appearance.spacing.small

            RowLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.normal

                CircularProgress { // the run has a deadline, so the wait is measurable
                    implicitSize: Appearance.font.pixelSize.hugeass
                    lineWidth: 3
                    value: AgentRun.progress
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.hairline

                    StyledText {
                        Layout.fillWidth: true
                        text: AgentRun.cancelling
                            ? Translation.tr("Stopping the agent")
                            : Translation.tr("The agent is working")
                        font.pixelSize: Appearance.font.pixelSize.small
                        font.weight: Font.DemiBold
                        color: Appearance.colors.colOnLayer2
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr("%1 of %2 · runs off this machine")
                            .arg(root.clock(root.elapsedSeconds))
                            .arg(root.clock(AgentRun.timeoutSec))
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                    }
                }

                DialogButton {
                    buttonText: Translation.tr("Cancel")
                    colEnabled: Appearance.colors.colError
                    enabled: !AgentRun.cancelling
                    activeFocusOnTab: true
                    onClicked: AgentRun.cancel()
                }
            }

            StyledText {
                Layout.fillWidth: true
                visible: AgentRun.task.length > 0
                text: AgentRun.task
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colOnLayer2
                wrapMode: Text.Wrap
                maximumLineCount: 3
                elide: Text.ElideRight
            }

            Rectangle {
                Layout.fillWidth: true
                visible: AgentRun.output.length > 0
                implicitHeight: Math.min(logText.implicitHeight + Appearance.spacing.small * 2, 180)
                radius: Appearance.rounding.verysmall
                color: Appearance.colors.colLayer1

                Flickable {
                    id: log
                    anchors.fill: parent
                    anchors.margins: Appearance.spacing.small
                    contentHeight: logText.implicitHeight
                    clip: true
                    interactive: contentHeight > height

                    StyledText {
                        id: logText
                        width: log.width
                        text: AgentRun.output
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                        onImplicitHeightChanged: log.contentY = Math.max(0, log.contentHeight - log.height)
                    }
                }
            }
        }
    }
}
