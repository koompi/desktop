import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft
import QtQuick
import QtQuick.Layouts

/**
 * The suggestion list, grouped by what a command is for. Entries arrive already
 * ordered; the grouping only draws the headings, so the index the keyboard moves
 * through and the order on screen are the same list.
 */
ColumnLayout {
    id: root

    // [{ value, label, description, groupTitle, badge }]
    property var entries: []
    property int selectedIndex: 0
    signal accepted(string value)

    readonly property var groups: {
        const out = [];
        let current = null;
        for (let i = 0; i < root.entries.length; i++) {
            const entry = root.entries[i];
            const title = entry.groupTitle ?? "";
            if (current === null || current.title !== title) {
                current = { title: title, items: [] };
                out.push(current);
            }
            current.items.push(Object.assign({}, entry, { flatIndex: i }));
        }
        return out;
    }

    spacing: 4

    Repeater {
        model: root.groups
        delegate: ColumnLayout {
            id: groupColumn
            required property var modelData
            Layout.fillWidth: true
            spacing: 2

            StyledText {
                visible: groupColumn.modelData.title.length > 0
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
                text: groupColumn.modelData.title
            }

            FlowButtonGroup {
                Layout.fillWidth: true
                spacing: 5

                Repeater {
                    model: groupColumn.modelData.items
                    delegate: ApiCommandButton {
                        id: entryButton
                        required property var modelData
                        readonly property bool selected: root.selectedIndex === entryButton.modelData.flatIndex
                        colBackground: selected ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                        bounce: false
                        Accessible.name: entryButton.modelData.label
                        Accessible.description: entryButton.modelData.description ?? ""

                        contentItem: RowLayout {
                            spacing: 4
                            StyledText {
                                font.pixelSize: Appearance.font.pixelSize.small
                                color: Appearance.m3colors.m3onSurface
                                text: entryButton.modelData.label
                            }
                            StyledText {
                                visible: (entryButton.modelData.badge ?? "").length > 0
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                color: Appearance.colors.colSubtext
                                text: entryButton.modelData.badge ?? ""
                            }
                        }

                        onHoveredChanged: {
                            if (entryButton.hovered)
                                root.selectedIndex = entryButton.modelData.flatIndex;
                        }
                        onClicked: root.accepted(entryButton.modelData.value)
                    }
                }
            }
        }
    }
}
