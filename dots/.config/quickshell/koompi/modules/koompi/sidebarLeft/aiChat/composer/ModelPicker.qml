import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Which model answers, chosen without leaving the sidebar. The list comes in
 * through `models` and the choice goes out through `picked`, so the component
 * knows nothing about the Ai singleton and a probe can drive it with three
 * fake rows. Up/Down move the highlight, Enter takes it, Escape and a click
 * outside close it (the owner listens for `dismissed`).
 */
FocusScope {
    id: root

    // [{ id, name, description }]
    property var models: []
    property string currentId: ""
    property int selectedIndex: -1
    property real maxHeight: 260
    readonly property int rowCount: rows.count

    signal picked(string id)
    signal dismissed()

    implicitHeight: sheet.implicitHeight

    function indexOf(id) {
        for (let i = 0; i < root.models.length; i++) {
            if (root.models[i].id === id)
                return i;
        }
        return -1;
    }

    function rowAt(index) {
        return rows.itemAt(index);
    }

    function moveSelection(step) {
        if (root.models.length === 0)
            return;
        const next = Math.min(root.models.length - 1, Math.max(0, root.selectedIndex + step));
        root.selectedIndex = next;
        root.revealRow(next);
    }

    function activateSelected() {
        if (root.selectedIndex < 0 || root.selectedIndex >= root.models.length)
            return;
        root.picked(root.models[root.selectedIndex].id);
    }

    function focusFirst() {
        root.forceActiveFocus(Qt.TabFocusReason);
    }

    // Keep the highlighted row inside the viewport when the list is taller than
    // the sheet allows.
    function revealRow(index) {
        const row = rows.itemAt(index);
        if (!row)
            return;
        if (row.y < list.contentY)
            list.contentY = row.y;
        else if (row.y + row.height > list.contentY + list.height)
            list.contentY = row.y + row.height - list.height;
    }

    onVisibleChanged: {
        if (visible) {
            root.selectedIndex = Math.max(0, root.indexOf(root.currentId));
            Qt.callLater(root.revealRow, root.selectedIndex);
        }
    }

    // Focus moving elsewhere (a Tab out, a click in the composer, the sidebar
    // closing) counts as a click outside.
    onActiveFocusChanged: {
        if (!root.activeFocus && root.visible)
            root.dismissed();
    }

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Up) {
            root.moveSelection(-1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.moveSelection(1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            root.activateSelected();
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.dismissed();
            event.accepted = true;
        }
    }

    Rectangle {
        id: sheet
        anchors {
            left: parent.left
            right: parent.right
            top: parent.top
        }
        color: Appearance.colors.colLayer2
        radius: Appearance.rounding.normal
        implicitHeight: sheetColumn.implicitHeight + 12 * 2
        clip: true

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
                    text: Translation.tr("Which model answers")
                }
                RippleButton {
                    implicitWidth: 24
                    implicitHeight: 24
                    buttonRadius: Appearance.rounding.full
                    focusPolicy: Qt.NoFocus
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

            StyledText {
                visible: root.models.length === 0
                Layout.fillWidth: true
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                text: Translation.tr("No models to choose from")
            }

            Flickable {
                id: list
                Layout.fillWidth: true
                implicitHeight: Math.min(rowColumn.implicitHeight, root.maxHeight)
                contentHeight: rowColumn.implicitHeight
                contentWidth: width
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                ColumnLayout {
                    id: rowColumn
                    width: list.width
                    spacing: 2

                    Repeater {
                        id: rows
                        model: root.models
                        delegate: RippleButton {
                            id: row
                            required property var modelData
                            required property int index
                            readonly property bool isCurrent: row.modelData.id === root.currentId
                            readonly property bool selected: root.selectedIndex === row.index

                            Layout.fillWidth: true
                            implicitHeight: rowContent.implicitHeight + 6 * 2
                            buttonRadius: Appearance.rounding.small
                            focusPolicy: Qt.NoFocus
                            colBackground: selected ? Appearance.colors.colSecondaryContainerHover : "transparent"
                            colBackgroundHover: Appearance.colors.colSecondaryContainerHover
                            Accessible.name: row.modelData.name
                            Accessible.description: row.modelData.description ?? ""

                            contentItem: RowLayout {
                                id: rowContent
                                spacing: 8

                                MaterialSymbol {
                                    Layout.leftMargin: 4
                                    text: "check"
                                    opacity: row.isCurrent ? 1 : 0
                                    iconSize: Appearance.font.pixelSize.larger
                                    color: Appearance.colors.colPrimary
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        font.pixelSize: Appearance.font.pixelSize.small
                                        font.weight: row.isCurrent ? Font.DemiBold : Font.Normal
                                        color: Appearance.m3colors.m3onSurface
                                        elide: Text.ElideRight
                                        text: row.modelData.name
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: (row.modelData.description ?? "").length > 0
                                        font.pixelSize: Appearance.font.pixelSize.smallest
                                        color: Appearance.colors.colSubtext
                                        elide: Text.ElideRight
                                        text: row.modelData.description ?? ""
                                    }
                                }
                            }

                            onHoveredChanged: {
                                if (row.hovered)
                                    root.selectedIndex = row.index;
                            }
                            onClicked: root.picked(row.modelData.id)
                        }
                    }
                }
            }
        }
    }
}
