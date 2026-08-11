pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft.aiChat.approval
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Every standing approval, in the same words the card used to grant it, and a
 * way to take each one back. Revoking here is the only supported way out; the
 * config file is the store, not the interface.
 */
ColumnLayout {
    id: root

    signal dismissed()

    readonly property var shellRules: Config.options?.ai?.approvals?.shellRules ?? []
    readonly property bool agentAllowed: Config.options?.ai?.approvals?.agent === true

    function revokeShellRule(rule: string) {
        Config.options.ai.approvals.shellRules = root.shellRules.filter(r => r !== rule);
    }

    function revokeAgent() {
        Config.options.ai.approvals.agent = false;
    }

    spacing: Appearance.spacing.normal

    RowLayout {
        Layout.fillWidth: true
        spacing: Appearance.spacing.normal

        MaterialSymbol {
            text: "verified_user"
            iconSize: Appearance.font.pixelSize.hugeass
            color: Appearance.colors.colOnLayer1
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.hairline

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("What runs without asking")
                font.pixelSize: Appearance.font.pixelSize.larger
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer1
            }

            StyledText {
                Layout.fillWidth: true
                text: Translation.tr("Granted by you, from an approval card. Revoke one and the next call asks again.")
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                wrapMode: Text.Wrap
            }
        }

        DialogButton {
            buttonText: Translation.tr("Close")
            activeFocusOnTab: true
            onClicked: root.dismissed()
        }
    }

    NoticeBox {
        Layout.fillWidth: true
        visible: root.agentAllowed
        materialIcon: ToolRisk.icon("leaves-machine")
        text: Translation.tr("The agent takes any task without asking. %1").arg(ToolRisk.sentence("leaves-machine"))

        DialogButton {
            buttonText: Translation.tr("Revoke")
            colEnabled: Appearance.colors.colError
            activeFocusOnTab: true
            onClicked: root.revokeAgent()
        }
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.shellRules.length === 0 && !root.agentAllowed
        text: Translation.tr("Nothing is allowed in advance. Every command will ask.")
        font.pixelSize: Appearance.font.pixelSize.small
        color: Appearance.colors.colSubtext
        wrapMode: Text.Wrap
    }

    StyledListView {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.shellRules.length > 0
        clip: true
        spacing: Appearance.spacing.small
        model: root.shellRules

        delegate: Rectangle {
            id: ruleItem
            required property string modelData
            readonly property bool wholeCommand: /[;|&><\n`]|\$\(/.test(ruleItem.modelData)

            width: ListView.view.width
            implicitHeight: ruleRow.implicitHeight + Appearance.spacing.normal * 2
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer2

            RowLayout {
                id: ruleRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Appearance.spacing.normal
                spacing: Appearance.spacing.normal

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: "terminal"
                    iconSize: Appearance.font.pixelSize.large
                    color: ToolRisk.accent("writes-system")
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Appearance.spacing.hairline

                    StyledText {
                        Layout.fillWidth: true
                        text: ruleItem.modelData
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                        wrapMode: Text.Wrap
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: ruleItem.wholeCommand
                            ? Translation.tr("This exact command only")
                            : Translation.tr("Any arguments")
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                        wrapMode: Text.Wrap
                    }
                }

                DialogButton {
                    buttonText: Translation.tr("Revoke")
                    colEnabled: Appearance.colors.colError
                    activeFocusOnTab: true
                    onClicked: root.revokeShellRule(ruleItem.modelData)
                }
            }
        }
    }
}
