pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.intelligence
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Every conversation the store knows about: search it, resume one, rename it,
 * delete it. D19's other half - the store itself is J03's.
 */
FocusScope {
    id: root

    property string query: ""

    // The rescue copies of a real conversation are the only surviving copy.
    // Nothing in this pane may rename or delete one.
    function protectedThread(id) {
        return String(id ?? "").toLowerCase().indexOf("rescue") >= 0;
    }

    readonly property var threads: {
        const all = Ai.threads ?? [];
        const needle = root.query.trim().toLowerCase();
        if (needle.length === 0)
            return all;
        return all.filter(thread => {
            const title = (thread.title ?? "").toLowerCase();
            return title.indexOf(needle) >= 0 || String(thread.id ?? "").toLowerCase().indexOf(needle) >= 0;
        });
    }

    Component.onCompleted: {
        Ai.refreshThreads();
        searchField.forceActiveFocus();
    }

    function resume(id) {
        Ai.openThread(id);
        IntelligenceContext.chatScrollY = -1;
        IntelligenceContext.currentPane = 0;
    }

    Keys.onPressed: event => {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            searchField.forceActiveFocus();
            searchField.selectAll();
            event.accepted = true;
        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_N) {
            Ai.newThread();
            IntelligenceContext.currentPane = 0;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.normal

        RowLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.small

            ToolbarTextField {
                id: searchField
                Layout.fillWidth: true
                Layout.fillHeight: false
                implicitHeight: 34
                placeholderText: Translation.tr("Search conversations…")
                onTextChanged: root.query = text

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Down || event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        threadList.forceActiveFocus();
                        if (threadList.currentIndex < 0)
                            threadList.currentIndex = 0;
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Escape) {
                        searchField.text = "";
                        event.accepted = true;
                    }
                }
            }

            IconToolbarButton {
                Layout.fillHeight: false
                implicitHeight: 34
                text: "refresh"
                onClicked: Ai.refreshThreads()
                Accessible.name: Translation.tr("Rescan the store")
                StyledToolTip {
                    text: Translation.tr("Rebuild the list from the files on disk")
                }
            }

            DialogButton {
                buttonText: Translation.tr("New conversation")
                onClicked: {
                    Ai.newThread();
                    IntelligenceContext.currentPane = 0;
                }
                StyledToolTip {
                    text: Translation.tr("Start a new thread (Ctrl+N)")
                }
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: threadList
                anchors.fill: parent
                clip: true
                spacing: Appearance.spacing.small
                visible: root.threads.length > 0
                model: root.threads
                currentIndex: 0
                keyNavigationEnabled: true

                delegate: ThreadRow {
                    id: threadRow
                    required property int index
                    required property var modelData
                    width: threadList.width
                    // The row the keyboard is on takes the focus, so F2 and Del
                    // reach it without the pointer ever being in the window.
                    focus: threadRow.ListView.isCurrentItem
                    thread: modelData
                    current: Ai.threadId === modelData.id
                    protectedThread: root.protectedThread(modelData.id)

                    onResumeRequested: root.resume(modelData.id)
                    onRenameAccepted: title => {
                        if (root.protectedThread(modelData.id))
                            return;
                        Ai.renameThread(modelData.id, title);
                    }
                    onDeleteRequested: {
                        if (root.protectedThread(modelData.id))
                            return;
                        Ai.deleteThread(modelData.id);
                    }

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (threadRow.confirmingDelete) {
                                threadRow.confirmingDelete = false;
                                Ai.deleteThread(modelData.id);
                            } else {
                                root.resume(modelData.id);
                            }
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Escape && threadRow.confirmingDelete) {
                            threadRow.confirmingDelete = false;
                            event.accepted = true;
                        } else if (event.key === Qt.Key_F2) {
                            threadRow.beginRename();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Delete) {
                            threadRow.confirmingDelete = !root.protectedThread(modelData.id);
                            event.accepted = true;
                        }
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Up && threadList.currentIndex === 0) {
                        searchField.forceActiveFocus();
                        event.accepted = true;
                    }
                }
            }

            PagePlaceholder {
                shown: root.threads.length === 0
                icon: root.query.length > 0 ? "search_off" : "history"
                title: root.query.length > 0 ? Translation.tr("Nothing matched") : Translation.tr("No conversations yet")
                description: root.query.length > 0
                    ? Translation.tr("No thread title carries those words.")
                    : Translation.tr("Ask the assistant something and the thread lands here with a title of its own.")
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: Translation.tr("%1 of %2 conversations · stored on this machine").arg(root.threads.length).arg((Ai.threads ?? []).length)
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colSubtext
        }
    }
}
