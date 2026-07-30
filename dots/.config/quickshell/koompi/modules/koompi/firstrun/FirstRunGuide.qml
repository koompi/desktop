import QtQuick
import QtQuick.Layouts
import qs.services
import qs.modules.common
import qs.modules.common.widgets

ContentSection {
    id: root
    icon: "explore"
    title: Translation.tr("Getting started")

    readonly property string superKey: Config.options.cheatsheet.superKey || "󰖳"

    // Every word the guide says lives in this list. A translation is a new file
    // under translations/, extracted from these Translation.tr() calls, so
    // adding one never touches the layout below.
    //
    // Four steps is the ceiling, not a starting set. A fifth thing belongs
    // somewhere the user goes looking for it, not in front of their first login.
    readonly property var steps: [
        {
            icon: "search",
            title: Translation.tr("Launch an application"),
            body: Translation.tr("Tap Super on its own, type a few letters of the name, then press Enter."),
            keys: [root.superKey]
        },
        {
            icon: "grid_view",
            title: Translation.tr("Switch workspaces"),
            body: Translation.tr("Hold Super and press a number to go to that workspace. Super and Tab together show them all."),
            keys: [root.superKey, "1"]
        },
        {
            icon: "settings",
            title: Translation.tr("Open settings"),
            body: Translation.tr("Appearance, bar, keyboard, network and the rest of the desktop, in one place."),
            keys: [root.superKey, "I"]
        },
        {
            icon: "keyboard_alt",
            title: Translation.tr("Find the keybind cheatsheet"),
            body: Translation.tr("Every shortcut this desktop knows, listed by what it does."),
            keys: [root.superKey, "/"]
        }
    ]

    Repeater {
        model: root.steps

        delegate: RowLayout {
            id: step
            required property var modelData

            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 12

            MaterialSymbol {
                Layout.alignment: Qt.AlignTop
                text: step.modelData.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colOnSecondaryContainer
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                StyledText {
                    Layout.fillWidth: true
                    text: step.modelData.title
                    font.weight: Font.Medium
                    color: Appearance.colors.colOnLayer0
                    wrapMode: Text.WordWrap
                }
                StyledText {
                    Layout.fillWidth: true
                    text: step.modelData.body
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    wrapMode: Text.WordWrap
                }
            }

            RowLayout {
                Layout.alignment: Qt.AlignTop
                spacing: 3

                Repeater {
                    model: step.modelData.keys

                    delegate: RowLayout {
                        id: cap
                        required property int index
                        required property string modelData

                        spacing: 3

                        StyledText {
                            visible: cap.index > 0
                            Layout.alignment: Qt.AlignVCenter
                            text: "+"
                        }
                        KeyboardKey {
                            Layout.alignment: Qt.AlignVCenter
                            key: cap.modelData
                        }
                    }
                }
            }
        }
    }
}
