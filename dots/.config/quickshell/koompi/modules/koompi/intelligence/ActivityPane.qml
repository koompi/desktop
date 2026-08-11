pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft.aiChat
import qs.modules.koompi.sidebarLeft.aiChat.activity
import qs.services
import QtQuick
import QtQuick.Layouts

/**
 * Everything the assistant did rather than said: the run still in flight at the
 * top, then every completed tool call in this thread, newest first. Both rows
 * are components that already exist - J08's live panel and J06's finished row.
 */
FocusScope {
    id: root

    // A tool result carries what came back; the assistant turn that asked for it
    // carries the arguments and the clock. Paired by id, never by position.
    readonly property var calls: {
        const ids = Ai.messageIDs ?? [];
        const byCallId = ({});
        for (let i = 0; i < ids.length; i++) {
            const message = Ai.messageByID[ids[i]];
            for (const call of (message?.toolCalls ?? [])) {
                if (call?.id)
                    byCallId[call.id] = {
                        "call": call,
                        "timestamp": message.timestamp ?? 0
                    };
            }
        }

        const rows = [];
        for (let i = ids.length - 1; i >= 0; i--) {
            const message = Ai.messageByID[ids[i]];
            if (!message)
                continue;
            const isToolResult = message.role === "tool" || (message.toolCallId ?? "").length > 0 || (message.functionResponse ?? "").length > 0;
            if (!isToolResult)
                continue;
            const asked = byCallId[message.toolCallId ?? ""];
            const args = asked?.call?.arguments;
            const start = asked?.timestamp ?? 0;
            const end = message.timestamp ?? 0;
            rows.push({
                "key": ids[i],
                "functionName": message.functionName ?? (asked?.call?.name ?? "tool"),
                "arguments": args === undefined || args === null ? "" : (typeof args === "string" ? args : JSON.stringify(args)),
                "response": message.functionResponse ?? message.rawContent ?? message.content ?? "",
                "elapsedMs": (start > 0 && end > start) ? (end - start) : -1
            });
        }
        return rows;
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.normal

        AgentActivityPanel {
            Layout.fillWidth: true
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("TOOL ACTIVITY")
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            font.letterSpacing: 1
            color: Appearance.colors.colSubtext
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: activityList
                anchors.fill: parent
                clip: true
                spacing: Appearance.spacing.small
                visible: root.calls.length > 0
                model: root.calls

                delegate: ToolActivityRow {
                    required property var modelData
                    width: activityList.width
                    functionName: modelData.functionName
                    arguments: modelData.arguments
                    response: modelData.response
                    elapsedMs: modelData.elapsedMs
                }
            }

            PagePlaceholder {
                shown: root.calls.length === 0
                icon: "bolt"
                title: Translation.tr("Nothing has run yet")
                description: Translation.tr("Shell commands, web searches and agent runs land here with what they returned and how long they took.")
            }
        }
    }
}
