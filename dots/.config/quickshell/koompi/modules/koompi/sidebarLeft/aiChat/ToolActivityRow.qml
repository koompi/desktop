pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Layouts

// Tool work is not dialogue. It renders as one row in the transcript - what ran,
// how long it took, what came back - and never as a chat bubble, whatever a
// visibility flag on the message says.
Item {
    id: root
    property string functionName: ""
    property string arguments: ""
    property string response: ""
    property real elapsedMs: -1
    property bool expanded: false

    readonly property string icon: {
        switch (root.functionName) {
        case "run_shell_command": return "terminal";
        case "search_web": return "travel_explore";
        case "fetch_url": return "link";
        case "ask_agent": return "smart_toy";
        case "remember": return "bookmark_add";
        case "recall": return "neurology";
        case "get_shell_config":
        case "set_shell_config": return "tune";
        case "set_owner_name": return "badge";
        default: return "build";
        }
    }

    readonly property string elapsedText: {
        if (!(root.elapsedMs >= 0)) return "";
        if (root.elapsedMs < 1000) return Math.round(root.elapsedMs) + " ms";
        if (root.elapsedMs < 60000) return (root.elapsedMs / 1000).toFixed(1) + " s";
        const total = Math.round(root.elapsedMs / 1000);
        return Math.floor(total / 60) + " m " + String(total % 60).padStart(2, "0") + " s";
    }

    readonly property string summary: {
        const lines = String(root.response ?? "").split("\n").map(l => l.trim()).filter(l => l.length > 0);
        if (lines.length === 0) return Translation.tr("no output");
        return lines.length > 1 ? Translation.tr("%1 (+%2 more lines)").arg(lines[0]).arg(lines.length - 1) : lines[0];
    }

    Layout.fillWidth: true
    implicitHeight: column.implicitHeight

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 0

        RippleButton {
            id: header
            Layout.fillWidth: true
            implicitHeight: headerRow.implicitHeight + 12
            buttonRadius: Appearance.rounding.small
            colBackground: Appearance.colors.colLayer1
            colBackgroundHover: Appearance.colors.colLayer1Hover
            colRipple: Appearance.colors.colLayer1Active
            focusPolicy: Qt.StrongFocus
            activeFocusOnTab: true

            Accessible.role: Accessible.Button
            Accessible.name: Translation.tr("Tool %1, %2. %3").arg(root.functionName).arg(root.elapsedText).arg(root.summary)
            Accessible.description: root.expanded ? Translation.tr("Hide the full output") : Translation.tr("Show the full output")

            onClicked: root.expanded = !root.expanded

            Rectangle { // focus ring, so the keyboard sees what the mouse sees
                anchors.fill: parent
                radius: Appearance.rounding.small
                color: "transparent"
                border.width: header.activeFocus ? 2 : 0
                border.color: Appearance.colors.colPrimary
            }

            contentItem: RowLayout {
                id: headerRow
                spacing: 8

                MaterialSymbol {
                    text: root.icon
                    iconSize: Appearance.font.pixelSize.large
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    text: root.functionName
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    font.family: Appearance.font.family.monospace
                    color: Appearance.colors.colOnLayer1
                }

                StyledText {
                    visible: root.elapsedText.length > 0
                    text: root.elapsedText
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }

                StyledText {
                    Layout.fillWidth: true
                    text: root.summary
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                }

                MaterialSymbol {
                    text: "keyboard_arrow_down"
                    iconSize: Appearance.font.pixelSize.normal
                    color: Appearance.colors.colOnLayer1
                    rotation: root.expanded ? 180 : 0
                    Behavior on rotation {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }
                }
            }
        }

        Item { // Body, revealed on expand
            Layout.fillWidth: true
            implicitHeight: root.expanded ? body.implicitHeight : 0
            clip: true

            Behavior on implicitHeight {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }

            Rectangle {
                id: body
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: bodyColumn.implicitHeight + 16
                radius: Appearance.rounding.small
                color: Appearance.colors.colLayer2

                ColumnLayout {
                    id: bodyColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: 8
                    spacing: 4

                    StyledText {
                        visible: root.arguments.length > 0
                        Layout.fillWidth: true
                        text: root.arguments
                        wrapMode: Text.Wrap
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smallie
                        color: Appearance.colors.colSubtext
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: root.response.length > 0 ? root.response : Translation.tr("no output")
                        wrapMode: Text.Wrap
                        font.family: Appearance.font.family.monospace
                        font.pixelSize: Appearance.font.pixelSize.smaller
                        color: Appearance.colors.colOnLayer2
                    }
                }
            }
        }
    }
}
