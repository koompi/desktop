pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.intelligence
import qs.modules.koompi.sidebarLeft.aiChat
import qs.modules.koompi.sidebarLeft.aiChat.approval
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * The same conversation the sidebar is showing, at a width a code block fits in.
 * Every message component here is J06's, unchanged - the pane only decides how
 * wide the column is and where the composer sits.
 */
FocusScope {
    id: root

    // A transcript that runs the whole width of a 1920 px screen is unreadable.
    readonly property real columnWidth: Math.min(920, root.width)

    Component.onCompleted: {
        if (IntelligenceContext.chatScrollY >= 0)
            transcript.contentY = IntelligenceContext.chatScrollY;
        else
            transcript.positionViewAtEnd();
        composer.forceActiveFocus();
    }

    Component.onDestruction: IntelligenceContext.chatScrollY = transcript.contentY

    function send() {
        const text = composer.text.trim();
        if (text.length === 0)
            return;
        composer.text = "";
        Ai.sendUserMessage(text);
        followTimer.restart();
    }

    Timer {
        id: followTimer
        interval: Appearance.animation.elementMoveFast.duration
        onTriggered: transcript.positionViewAtEnd()
    }

    Connections {
        target: Ai
        function onTokenStreamed() {
            if (transcript.atYEnd)
                transcript.positionViewAtEnd();
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: Appearance.spacing.normal

        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            StyledListView {
                id: transcript
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                width: root.columnWidth
                clip: true
                spacing: Appearance.spacing.normal
                visible: Ai.messageIDs.length > 0
                model: Ai.messageIDs
                cacheBuffer: 4000

                // Not a layout: AiMessage anchors itself to its parent's edges,
                // which a QtQuick layout manages and warns about.
                delegate: Item {
                    id: messageDelegate
                    required property int index
                    required property var modelData
                    readonly property var messageObject: Ai.messageByID[messageDelegate.modelData]
                    width: transcript.width
                    implicitHeight: message.implicitHeight + (approval.active ? approval.implicitHeight + Appearance.spacing.small : 0)

                    AiMessage {
                        id: message
                        messageIndex: messageDelegate.index
                        messageData: messageDelegate.messageObject
                        messageInputField: composer
                        enableMouseSelection: true
                    }

                    // A command waiting on a decision has to be answerable here
                    // too, or the full window is a dead end for any tool call.
                    Loader {
                        id: approval
                        anchors.top: message.bottom
                        anchors.topMargin: Appearance.spacing.small
                        anchors.left: parent.left
                        anchors.right: parent.right
                        active: messageDelegate.messageObject?.functionPending ?? false
                        sourceComponent: ApprovalCard {
                            messageData: messageDelegate.messageObject
                        }
                    }
                }

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Home) {
                        transcript.positionViewAtBeginning();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_End) {
                        transcript.positionViewAtEnd();
                        event.accepted = true;
                    }
                }
            }

            PagePlaceholder {
                shown: Ai.messageIDs.length === 0
                icon: "forum"
                title: Translation.tr("Nothing asked yet")
                description: Translation.tr("This machine answers on its own. Ask it something, or open Threads to pick up where you left off.")
            }
        }

        Rectangle { // composer
            Layout.alignment: Qt.AlignHCenter
            Layout.preferredWidth: root.columnWidth
            implicitHeight: composerRow.implicitHeight + Appearance.spacing.normal * 2
            radius: Appearance.rounding.normal
            color: Appearance.colors.colLayer1
            border.width: 1
            border.color: composer.activeFocus ? Appearance.colors.colPrimary : Appearance.colors.colOutlineVariant

            RowLayout {
                id: composerRow
                anchors {
                    fill: parent
                    margins: Appearance.spacing.normal
                }
                spacing: Appearance.spacing.small

                ScrollView {
                    Layout.fillWidth: true
                    implicitHeight: Math.min(160, Math.max(34, composer.implicitHeight))

                    StyledTextArea {
                        id: composer
                        wrapMode: TextEdit.Wrap
                        placeholderText: Translation.tr("Ask anything. Enter sends, Shift+Enter starts a line.")
                        background: null

                        Keys.onPressed: event => {
                            if ((event.key === Qt.Key_Return || event.key === Qt.Key_Enter) && !(event.modifiers & Qt.ShiftModifier)) {
                                root.send();
                                event.accepted = true;
                            }
                        }
                    }
                }

                IconToolbarButton {
                    Layout.fillHeight: false
                    implicitHeight: 34
                    text: Ai.requestActive ? "stop" : "send"
                    onClicked: {
                        if (Ai.requestActive)
                            Ai.cancelRequest();
                        else
                            root.send();
                    }
                    Accessible.name: Ai.requestActive ? Translation.tr("Stop the answer") : Translation.tr("Send")
                    StyledToolTip {
                        text: Ai.requestActive ? Translation.tr("Stop and free the model's slot") : Translation.tr("Send (Enter)")
                    }
                }
            }
        }
    }
}
