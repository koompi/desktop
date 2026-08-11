pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft.aiChat.approval
import qs.services
import Quickshell
import QtQuick
import QtQuick.Layouts

/**
 * The decision surface for a tool call waiting on the user. It states the tool,
 * what it will act on, the reason the model gave and what the risk is, and it
 * says in words what "Always allow" will cover before the click - the rule the
 * engine will actually store, not a friendlier version of it.
 */
Rectangle {
    id: root

    property var messageData
    property string fallbackTarget: ""
    property string fallbackToolName: "run_shell_command"

    // The arguments the engine will pass, never the fence rendered from them: a
    // card that shows one command and runs another is the bug worth preventing.
    readonly property string target: {
        const args = root.messageData?.functionCall?.args ?? null;
        if (!args) return root.fallbackTarget;
        return String(args.command ?? args.task ?? root.fallbackTarget);
    }

    readonly property string toolName: root.messageData?.functionCall?.name ?? root.fallbackToolName
    readonly property bool isAgent: root.toolName === "ask_agent"
    readonly property string risk: Ai.riskOf(root.toolName)
    readonly property bool canRemember: Ai.approvalOf(root.toolName) === "once"
    readonly property string rule: root.isAgent ? "" : Ai.commandRule(String(root.target))
    // Ask the engine rather than re-test for metacharacters here: a rule that still
    // keys on the program name survives an argument being appended to it.
    readonly property bool ruleIsWholeCommand: Ai.commandRule(`${root.rule} x`) !== root.rule

    // The model's own words, taken from what it wrote before the tool layer
    // appended its request. No reason is better than an invented one.
    readonly property string reason: {
        const raw = String(root.messageData?.rawContent ?? "");
        const fence = raw.lastIndexOf("```");
        const head = fence > 0 ? raw.slice(0, raw.lastIndexOf("```", fence - 1)) : raw;
        const lines = head.replace(/\*\*[^*\n]*\*\*\s*$/, "").split("\n")
            .map(l => l.replace(/[*`#]/g, "").trim())
            .filter(l => l.length > 0);
        return lines.length > 0 ? lines[lines.length - 1] : "";
    }

    readonly property string scopeSentence: {
        if (!root.canRemember)
            return Translation.tr("This tool asks every time. Nothing here can be remembered.");
        if (root.isAgent)
            return Translation.tr("\"Always allow\" lets the agent take any task, without asking, until you revoke it.");
        if (root.ruleIsWholeCommand)
            return Translation.tr("\"Always allow\" covers this one command, character for character, because it uses shell syntax. Change a single character and it asks again.");
        return Translation.tr("\"Always allow\" covers every command starting with `%1`, whatever arguments follow it. Any other program still asks.").arg(root.rule);
    }

    Layout.fillWidth: true
    implicitHeight: layout.implicitHeight + Appearance.spacing.large * 2
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2
    border.width: 1
    border.color: ToolRisk.container(root.risk)

    ColumnLayout {
        id: layout
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: Appearance.spacing.large
        spacing: Appearance.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.normal

            MaterialSymbol {
                text: root.isAgent ? "smart_toy" : "terminal"
                iconSize: Appearance.font.pixelSize.hugeass
                color: ToolRisk.accent(root.risk)
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Appearance.spacing.hairline

                StyledText {
                    Layout.fillWidth: true
                    text: root.isAgent
                        ? Translation.tr("The assistant wants to hand this task to the agent")
                        : Translation.tr("The assistant wants to run a command")
                    font.pixelSize: Appearance.font.pixelSize.normal
                    font.weight: Font.DemiBold
                    color: Appearance.colors.colOnLayer2
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr("%1 · %2").arg(root.toolName).arg(ToolRisk.label(root.risk))
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                }
            }
        }

        Rectangle { // What it is asking for, in its own words
            Layout.fillWidth: true
            implicitHeight: fields.implicitHeight + Appearance.spacing.normal * 2
            radius: Appearance.rounding.verysmall
            color: Appearance.colors.colLayer1

            GridLayout {
                id: fields
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: Appearance.spacing.normal
                columns: 2
                columnSpacing: Appearance.spacing.normal
                rowSpacing: Appearance.spacing.hairline

                StyledText {
                    Layout.alignment: Qt.AlignTop
                    text: Translation.tr("tool")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: root.toolName
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.alignment: Qt.AlignTop
                    text: root.isAgent ? Translation.tr("task") : Translation.tr("command")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    text: String(root.target).trim()
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ToolRisk.accent(root.risk)
                    wrapMode: Text.Wrap
                }

                StyledText {
                    Layout.alignment: Qt.AlignTop
                    visible: root.reason.length > 0
                    text: Translation.tr("reason")
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                }
                StyledText {
                    Layout.fillWidth: true
                    visible: root.reason.length > 0
                    text: root.reason
                    font.family: Appearance.font.family.monospace
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colOnLayer1
                    wrapMode: Text.Wrap
                }
            }
        }

        Rectangle { // Where the data goes. Amber-equivalent when it leaves.
            Layout.fillWidth: true
            implicitHeight: localityRow.implicitHeight + Appearance.spacing.normal * 2
            radius: Appearance.rounding.verysmall
            color: ToolRisk.container(root.risk)

            RowLayout {
                id: localityRow
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.margins: Appearance.spacing.normal
                spacing: Appearance.spacing.small

                MaterialSymbol {
                    Layout.alignment: Qt.AlignTop
                    text: ToolRisk.icon(root.risk)
                    iconSize: Appearance.font.pixelSize.large
                    color: ToolRisk.accent(root.risk)
                }

                StyledText {
                    Layout.fillWidth: true
                    text: ToolRisk.sentence(root.risk)
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: ToolRisk.accent(root.risk)
                    wrapMode: Text.Wrap
                }
            }
        }

        StyledText { // The scope, before the click, not after it
            Layout.fillWidth: true
            text: root.scopeSentence
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
            wrapMode: Text.Wrap
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            DialogButton {
                buttonText: Translation.tr("Allowed rules")
                colEnabled: Appearance.colors.colSubtext
                activeFocusOnTab: true
                onClicked: {
                    const page = SettingsPages.list.find(entry => entry.component.endsWith("AiConfig.qml"));
                    if (page)
                        SettingsPages.open(page);
                }
                StyledToolTip {
                    text: Translation.tr("Opens Settings > AI: everything you have allowed without asking, and a way to take it back")
                }
            }

            Item { Layout.fillWidth: true }

            DialogButton {
                buttonText: Translation.tr("Reject")
                colEnabled: Appearance.colors.colError
                activeFocusOnTab: true
                onClicked: Ai.rejectCommand(root.messageData)
            }

            DialogButton {
                visible: root.canRemember
                buttonText: Translation.tr("Always allow")
                activeFocusOnTab: true
                onClicked: Ai.approveCommand(root.messageData, true)
            }

            DialogButton {
                buttonText: Translation.tr("Allow once")
                colBackground: Appearance.colors.colPrimary
                colBackgroundHover: Appearance.colors.colPrimaryHover
                colRipple: Appearance.colors.colPrimaryActive
                colEnabled: Appearance.colors.colOnPrimary
                activeFocusOnTab: true
                onClicked: Ai.approveCommand(root.messageData, false)
            }
        }
    }

}
