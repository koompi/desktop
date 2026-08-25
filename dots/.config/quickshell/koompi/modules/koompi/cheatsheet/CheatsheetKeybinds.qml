pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property real padding: 4
    property var categoryColumns: [
        ["Shell", "Kiri"],
        ["App", ""],
        ["Utilities", "Screen", "Media"],
        ["Window", "Workspace", "Session"],
    ]
    implicitWidth: QsWindow?.window?.screen.width * 0.7 ?? 0
    implicitHeight: QsWindow?.window?.screen.height * 0.7 ?? 0

    readonly property string query: searchField.text
    // Descriptions run long enough for a subsequence to match almost anywhere,
    // so the same floor Search puts under window titles.
    readonly property real scoreThreshold: 0.5
    readonly property var prepared: HyprlandKeybinds.keybinds.map(bind => ({
        name: Fuzzy.prepare(HyprlandKeybinds.searchText(bind)),
        bind: bind
    }))
    // Ids of the rows the query keeps, best first; null while there is no query.
    readonly property var matchIds: {
        if (root.query.trim() === "")
            return null;
        return Fuzzy.go(root.query, root.prepared, {
            all: true,
            key: "name",
            threshold: root.scoreThreshold
        }).map(result => result.obj.bind.id);
    }
    // What Enter runs: the best match that is shown and can be dispatched.
    readonly property var firstMatch: {
        if (root.matchIds === null)
            return null;
        for (const id of root.matchIds) {
            const bind = HyprlandKeybinds.keybinds[id];
            if (bind.description.length > 0 && HyprlandKeybinds.dispatchable(bind))
                return bind;
        }
        return null;
    }

    function categoriesForColumn(columnIndex) {
        const categories = root.categoryColumns[columnIndex].slice();
        if (columnIndex !== 0)
            return categories;

        const assigned = root.categoryColumns.reduce((all, column) => all.concat(column), []);
        HyprlandKeybinds.keybindCategories.forEach(category => {
            if (!assigned.includes(category))
                categories.push(category);
        });
        return categories;
    }

    // The bind's own surface opening after the cheatsheet has gone is the point.
    function activate(bind) {
        HyprlandKeybinds.dispatch(bind);
        GlobalStates.cheatsheetOpen = false;
    }

    Connections {
        target: GlobalStates
        function onCheatsheetOpenChanged() {
            if (!GlobalStates.cheatsheetOpen)
                return;
            searchField.text = "";
            searchField.forceActiveFocus();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Appearance.rounding.small
        spacing: 10

        ToolbarTextField {
            id: searchField
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: 360
            placeholderText: Translation.tr("Search keybinds, Enter runs the first")
            onAccepted: {
                if (root.SwipeView.isCurrentItem && root.firstMatch !== null)
                    root.activate(root.firstMatch);
            }
            // A query clears first; an empty field lets Escape reach the sheet, which closes.
            Keys.onEscapePressed: event => {
                event.accepted = text.length > 0;
                text = "";
            }
        }

        Row {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 10

            Repeater {
                model: root.categoryColumns.length
                delegate: Column {
                    id: categoryColumn
                    required property int index
                    width: (parent.width - parent.spacing * (root.categoryColumns.length - 1)) / root.categoryColumns.length
                    spacing: 10

                    Repeater {
                        model: root.categoriesForColumn(categoryColumn.index)
                        delegate: CheatsheetKeybindsCategory {
                            required property var modelData
                            categoryName: modelData
                            matchIds: root.matchIds
                            firstMatchId: root.firstMatch?.id ?? -1
                            activate: root.activate
                        }
                    }
                }
            }
        }
    }
}
