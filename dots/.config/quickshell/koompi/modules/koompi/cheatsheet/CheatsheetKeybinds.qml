pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import QtQuick
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

    Row {
        anchors.fill: parent
        anchors.margins: Appearance.rounding.small
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
                    }
                }
            }
        }
    }
}
