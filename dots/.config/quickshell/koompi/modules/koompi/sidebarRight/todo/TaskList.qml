import qs.modules.common
import qs.modules.common.widgets
import qs.services
import Qt5Compat.GraphicalEffects
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    required property var taskList
    property string emptyPlaceholderIcon
    property string emptyPlaceholderText
    property int todoListItemSpacing: 4
    property int todoListItemPadding: 5
    property int listBottomPadding: 80

    StyledListView {
        id: listView
        anchors.fill: parent
        spacing: root.todoListItemSpacing
        animateAppearance: false
        model: ScriptModel {
            values: root.taskList
        }
        delegate: Item {
            id: todoItem
            required property var modelData
            required property int index

            implicitHeight: todoItemRectangle.implicitHeight
            width: ListView.view.width
            clip: false
            z: dragHandleArea.drag.active ? 2 : 1

            Rectangle {
                id: todoItemRectangle
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom
                implicitHeight: todoContentRow.implicitHeight
                color: Appearance.colors.colLayer2
                radius: Appearance.rounding.small
                opacity: dragHandleArea.drag.active ? 0.82 : 1.0

                // Expose model data so DropArea in other delegates can identify the source
                property var wrapperData: todoItem.modelData

                Drag.active: dragHandleArea.drag.active
                Drag.source: todoItemRectangle
                Drag.keys: ["todo-item"]
                Drag.hotSpot.x: width / 2
                Drag.hotSpot.y: height / 2

                states: State {
                    when: dragHandleArea.drag.active
                    AnchorChanges {
                        target: todoItemRectangle
                        anchors.left: undefined
                        anchors.right: undefined
                        anchors.bottom: undefined
                    }
                    PropertyChanges {
                        target: todoItemRectangle
                        width: todoItem.width
                        x: 0
                    }
                }

                RowLayout {
                    id: todoContentRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 0

                    // Drag handle — only for undone tasks
                    Item {
                        id: dragHandleItem
                        visible: !todoItem.modelData.done
                        implicitWidth: visible ? 26 : 0
                        Layout.fillHeight: true

                        MaterialSymbol {
                            anchors.centerIn: parent
                            text: "drag_indicator"
                            iconSize: 16
                            color: Appearance.colors.colSubtext
                        }

                        MouseArea {
                            id: dragHandleArea
                            anchors.fill: parent
                            cursorShape: Qt.DragMoveCursor
                            drag.target: todoItemRectangle
                            drag.axis: Drag.YAxis
                            drag.threshold: 6
                            drag.minimumY: -todoItem.y
                            drag.maximumY: listView.contentHeight - todoItem.y - todoItemRectangle.implicitHeight
                        }
                    }

                    StyledText {
                        id: todoContentText
                        Layout.fillWidth: true
                        Layout.leftMargin: todoItem.modelData.done ? 10 : 2
                        Layout.rightMargin: 4
                        Layout.topMargin: root.todoListItemPadding
                        Layout.bottomMargin: root.todoListItemPadding
                        Layout.alignment: Qt.AlignVCenter
                        text: todoItem.modelData.content
                        wrapMode: Text.Wrap
                    }

                    TodoItemActionButton {
                        Layout.fillWidth: false
                        Layout.alignment: Qt.AlignVCenter
                        onClicked: {
                            if (!todoItem.modelData.done)
                                Todo.markDone(todoItem.modelData.originalIndex);
                            else
                                Todo.markUnfinished(todoItem.modelData.originalIndex);
                        }
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: todoItem.modelData.done ? "remove_done" : "check"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                    }

                    TodoItemActionButton {
                        Layout.fillWidth: false
                        Layout.alignment: Qt.AlignVCenter
                        Layout.rightMargin: 4
                        onClicked: Todo.deleteItem(todoItem.modelData.originalIndex)
                        contentItem: MaterialSymbol {
                            anchors.centerIn: parent
                            horizontalAlignment: Text.AlignHCenter
                            text: "delete_forever"
                            iconSize: Appearance.font.pixelSize.larger
                            color: Appearance.colors.colOnLayer1
                        }
                    }
                }
            }

            // Drop target: fires when another item is dragged over this one
            DropArea {
                anchors.fill: parent
                keys: ["todo-item"]
                onEntered: {
                    const src = drag.source;
                    if (src && src !== todoItemRectangle) {
                        const srcOrigIdx = src.wrapperData?.originalIndex ?? -1;
                        const tgtOrigIdx = todoItem.modelData.originalIndex;
                        if (srcOrigIdx !== -1 && srcOrigIdx !== tgtOrigIdx)
                            Todo.moveItem(srcOrigIdx, tgtOrigIdx);
                    }
                }
            }
        }
    }

    Item {
        // Placeholder when list is empty
        visible: opacity > 0
        opacity: taskList.length === 0 ? 1 : 0
        anchors.fill: parent

        Behavior on opacity {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        ColumnLayout {
            anchors.centerIn: parent
            spacing: 5

            MaterialSymbol {
                Layout.alignment: Qt.AlignHCenter
                iconSize: 55
                color: Appearance.m3colors.m3outline
                text: emptyPlaceholderIcon
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                font.pixelSize: Appearance.font.pixelSize.normal
                color: Appearance.m3colors.m3outline
                horizontalAlignment: Text.AlignHCenter
                text: emptyPlaceholderText
            }
        }
    }
}
