pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.intelligence
import qs.modules.koompi.sidebarLeft.aiChat
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * D32: what the model is about to be given, itemised, with the budget it spends
 * and a control that takes any of it back out. Underneath, what the last answer
 * actually rested on, in J06's own source rows.
 */
FocusScope {
    id: root

    readonly property var items: IntelligenceContext.contextItems
    readonly property var sources: IntelligenceContext.lastAnswerSources
    readonly property int droppedCount: root.items.filter(item => item.dropped).length

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.normal

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.hairline

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("Going into the next turn")
                    font.pixelSize: Appearance.font.pixelSize.large
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    Layout.fillWidth: true
                    text: IntelligenceContext.contextWindow > 0
                        ? Translation.tr("%1 items · %2 of the model's %3-token window")
                            .arg(root.items.length).arg(IntelligenceContext.contextTokens).arg(IntelligenceContext.contextWindow)
                        : Translation.tr("%1 items · the model has not reported a window").arg(root.items.length)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
            }

            DialogButton {
                visible: root.droppedCount > 0
                buttonText: Translation.tr("Put back %1").arg(root.droppedCount)
                onClicked: IntelligenceContext.restoreAll()
            }
        }

        ContextBudgetBar {
            Layout.fillWidth: true
        }

        StyledListView {
            id: itemList
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Appearance.spacing.small
            model: root.items

            delegate: ContextItemRow {
                required property var modelData
                width: itemList.width
                item: modelData
                onDropRequested: IntelligenceContext.dropItem(modelData)
                onRestoreRequested: IntelligenceContext.restoreMemory(modelData.memoryId)
            }
        }

        StyledText {
            visible: root.sources.length > 0
            Layout.fillWidth: true
            text: Translation.tr("WHAT THE LAST ANSWER USED")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            font.letterSpacing: 1
            color: Appearance.colors.colSubtext
        }

        ColumnLayout {
            Layout.fillWidth: true
            visible: root.sources.length > 0
            spacing: Appearance.spacing.small

            Repeater {
                model: root.sources

                MessageSourceRow {
                    required property var modelData
                    Layout.fillWidth: true
                    sourceType: modelData.type ?? "web"
                    name: modelData.name ?? ""
                    detail: modelData.detail ?? ""
                    score: modelData.score ?? NaN
                    url: modelData.url ?? ""
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            MaterialSymbol {
                text: "lock"
                iconSize: Appearance.font.pixelSize.normal
                color: Appearance.colors.colPrimary
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Nothing here is uploaded. Dropping a source keeps it out of the request the next message builds.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }
    }
}
