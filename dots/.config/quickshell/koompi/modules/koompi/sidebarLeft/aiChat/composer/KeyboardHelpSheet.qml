import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

/**
 * Every key this chat listens for. One list, so a binding that is not here is a
 * binding that does not exist.
 */
Rectangle {
    id: root

    property bool shown: false
    signal dismissed()

    readonly property var bindings: [
        { keys: ["Enter"], action: Translation.tr("Send") },
        { keys: ["Shift", "Enter"], action: Translation.tr("New line") },
        { keys: ["Tab"], action: Translation.tr("Take the highlighted suggestion, or step into the messages") },
        { keys: ["Shift", "Tab"], action: Translation.tr("Back to the composer") },
        { keys: ["Esc"], action: Translation.tr("Stop the answer, drop the attachment, then close") },
        { keys: ["↑", "↓"], action: Translation.tr("Move through suggestions") },
        { keys: ["Alt", "↑"], action: Translation.tr("Something you sent earlier") },
        { keys: ["Alt", "↓"], action: Translation.tr("Something you sent later") },
        { keys: ["Ctrl", "K"], action: Translation.tr("Open the command palette") },
        { keys: ["Ctrl", "R"], action: Translation.tr("Ask the last turn again") },
        { keys: ["Ctrl", "End"], action: Translation.tr("Jump to the newest message (empty composer)") },
        { keys: ["Ctrl", "Home"], action: Translation.tr("Jump to the first message (empty composer)") },
        { keys: ["PgUp", "PgDn"], action: Translation.tr("Scroll the messages") },
        { keys: ["Ctrl", "V"], action: Translation.tr("Paste; an image or file is attached instead") },
        { keys: ["Ctrl", "Shift", "O"], action: Translation.tr("Clear the chat") },
        { keys: ["F1"], action: Translation.tr("This list") }
    ]

    color: Appearance.colors.colLayer2
    radius: Appearance.rounding.normal
    implicitHeight: shown ? (sheetColumn.implicitHeight + 12 * 2) : 0
    visible: implicitHeight > 0
    clip: true

    Behavior on implicitHeight {
        animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
    }

    ColumnLayout {
        id: sheetColumn
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
            margins: 12
        }
        spacing: 4

        RowLayout {
            Layout.fillWidth: true
            StyledText {
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colOnLayer2
                text: Translation.tr("Keys")
            }
            RippleButton {
                implicitWidth: 24
                implicitHeight: 24
                buttonRadius: Appearance.rounding.full
                Accessible.name: Translation.tr("Close")
                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    text: "close"
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: Appearance.font.pixelSize.larger
                    color: Appearance.colors.colOnSurfaceVariant
                }
                onClicked: root.dismissed()
            }
        }

        Repeater {
            model: root.bindings
            delegate: RowLayout {
                id: bindingRow
                required property var modelData
                Layout.fillWidth: true
                spacing: 4

                Repeater {
                    model: bindingRow.modelData.keys
                    delegate: KeyboardKey {
                        required property string modelData
                        key: modelData
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    font.pixelSize: Appearance.font.pixelSize.smaller
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.Wrap
                    text: bindingRow.modelData.action
                }
            }
        }
    }
}
