import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell

Item {
    id: root
    property int messageIndex
    property var messageData
    property var messageInputField

    property real messagePadding: 10
    property real contentSpacing: 3
    property real avatarSize: 28
    property bool showAvatar: root.isUser || root.isAssistant
    property real avatarSpace: showAvatar ? (avatarSize + 6) : 0

    property bool enableMouseSelection: false
    property bool renderMarkdown: true
    property bool editing: false

    property bool isUser: messageData?.role == 'user'
    property bool isInterface: messageData?.role == 'interface'
    property bool isAssistant: messageData?.role == 'assistant'

    property list<var> messageBlocks: []

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: outerColumn.implicitHeight

    function recomputeBlocks() {
        messageBlocks = StringUtils.splitMarkdownBlocks(root.messageData?.content)
    }

    onMessageDataChanged: recomputeBlocks()
    Component.onCompleted: recomputeBlocks()

    Timer {
        id: throttleTimer
        interval: 120
        repeat: false
        onTriggered: root.recomputeBlocks()
    }

    Connections {
        target: root.messageData
        function onContentChanged() {
            if (root.messageData.done) root.recomputeBlocks();
            else if (!throttleTimer.running) throttleTimer.start();
        }
        function onDoneChanged() {
            throttleTimer.stop();
            root.recomputeBlocks();
        }
    }

    function saveMessage() {
        if (!root.editing) return;
        // Get all Loader children (each represents a segment)
        const segments = messageContentColumnLayout.children
            .map(child => child.segment)
            .filter(segment => (segment));

        // Reconstruct markdown
        const newContent = segments.map(segment => {
            if (segment.type === "code") {
                const lang = segment.lang ? segment.lang : "";
                // Remove trailing newlines
                const code = segment.content.replace(/\n+$/, "");
                return "```" + lang + "\n" + code + "\n```";
            } else {
                return segment.content;
            }
        }).join("");

        root.editing = false
        root.messageData.content = newContent;
    }

    Keys.onPressed: (event) => {
        if ( // Prevent de-select
            event.key === Qt.Key_Control ||
            event.key == Qt.Key_Shift ||
            event.key == Qt.Key_Alt ||
            event.key == Qt.Key_Meta
        ) {
            event.accepted = true
        }
        // Ctrl + S to save
        if ((event.key === Qt.Key_S) && event.modifiers == Qt.ControlModifier) {
            root.saveMessage();
            event.accepted = true;
        }
    }

    HoverHandler { id: messageHover }

    ColumnLayout {
        id: outerColumn
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: 2

        Item { // Bubble row (aligns the bubble left/right)
            Layout.fillWidth: true
            implicitHeight: bubble.implicitHeight

            Rectangle { // Sender avatar
                id: avatar
                visible: root.showAvatar
                y: 0
                x: root.isUser ? (parent.width - width) : 0
                implicitWidth: root.avatarSize
                implicitHeight: root.avatarSize
                radius: width / 2
                color: root.isUser ? Appearance.colors.colLayer2 : Appearance.colors.colLayer1

                MaterialSymbol { // User avatar
                    visible: root.isUser
                    anchors.centerIn: parent
                    iconSize: root.avatarSize * 0.62
                    color: Appearance.colors.colOnLayer2
                    text: "person"
                }

                CustomIcon { // Assistant avatar: KOOMPI logo
                    visible: root.isAssistant
                    anchors.centerIn: parent
                    width: root.avatarSize * 0.7
                    height: root.avatarSize * 0.7
                    source: "koompi-symbolic.svg"
                    colorize: true
                    color: Appearance.colors.colOnLayer1
                }
            }

            Rectangle {
                id: bubble
                y: 0
                x: root.isUser ? (parent.width - width - root.avatarSpace) : root.avatarSpace
                radius: Appearance.rounding.normal
                color: root.isUser ? Appearance.colors.colLayer2
                    : root.isInterface ? "transparent"
                    : Appearance.colors.colLayer1
                implicitHeight: contentColumn.implicitHeight + root.messagePadding * 2
                width: Math.min(contentColumn.implicitWidth + root.messagePadding * 2,
                    (parent.width - root.avatarSpace) * (root.isUser ? 0.82 : root.isInterface ? 1.0 : 0.92))

                ColumnLayout {
                    id: contentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.messagePadding
                    spacing: root.contentSpacing

                    Loader {
                        Layout.fillWidth: true
                        active: root.messageData?.localFilePath && root.messageData?.localFilePath.length > 0
                        sourceComponent: AttachedFileIndicator {
                            filePath: root.messageData?.localFilePath
                            canRemove: false
                        }
                    }

                    ColumnLayout { // Message content
                        id: messageContentColumnLayout
                        Layout.fillWidth: true
                        spacing: 0

                        Item {
                            Layout.fillWidth: true
                            implicitHeight: loadingIndicatorLoader.shown ? loadingIndicatorLoader.implicitHeight : 0
                            implicitWidth: loadingIndicatorLoader.implicitWidth
                            visible: implicitHeight > 0

                            Behavior on implicitHeight {
                                animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
                            }
                            FadeLoader {
                                id: loadingIndicatorLoader
                                anchors.centerIn: parent
                                shown: (root.messageBlocks.length < 1) && (!root.messageData.done)
                                sourceComponent: MaterialLoadingIndicator {
                                    loading: true
                                }
                            }
                        }
                        Repeater {
                            model: ScriptModel {
                                values: root.messageBlocks
                            }
                            delegate: DelegateChooser {
                                id: messageDelegate
                                role: "type"

                                DelegateChoice { roleValue: "code"; MessageCodeBlock {
                                    editing: root.editing
                                    renderMarkdown: root.renderMarkdown
                                    enableMouseSelection: root.enableMouseSelection
                                    segmentContent: modelData.content
                                    segmentLang: modelData.lang
                                    messageData: root.messageData
                                } }
                                DelegateChoice { roleValue: "think"; MessageThinkBlock {
                                    editing: root.editing
                                    renderMarkdown: root.renderMarkdown
                                    enableMouseSelection: root.enableMouseSelection
                                    segmentContent: modelData.content
                                    messageData: root.messageData
                                    done: root.messageData?.done ?? false
                                    completed: modelData.completed ?? false
                                } }
                                DelegateChoice { roleValue: "text"; MessageTextBlock {
                                    editing: root.editing
                                    renderMarkdown: root.renderMarkdown
                                    enableMouseSelection: root.enableMouseSelection
                                    segmentContent: modelData.content
                                    messageData: root.messageData
                                    done: root.messageData?.done ?? false
                                    forceDisableChunkSplitting: root.messageData?.content.includes("```") ?? true
                                } }
                            }
                        }
                    }

                    Flow { // Annotations
                        visible: root.messageData?.annotationSources?.length > 0
                        spacing: 5
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft

                        Repeater {
                            model: ScriptModel {
                                values: root.messageData?.annotationSources || []
                            }
                            delegate: AnnotationSourceButton {
                                required property var modelData
                                displayText: modelData.text
                                url: modelData.url
                            }
                        }
                    }

                    Flow { // Search queries
                        visible: root.messageData?.searchQueries?.length > 0
                        spacing: 5
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignLeft

                        Repeater {
                            model: ScriptModel {
                                values: root.messageData?.searchQueries || []
                            }
                            delegate: SearchQueryButton {
                                required property var modelData
                                query: modelData
                            }
                        }
                    }
                }
            }
        }

        Item { // Controls row, revealed on hover, aligned to the message side
            Layout.fillWidth: true
            implicitHeight: controlsRow.implicitHeight
            opacity: messageHover.hovered ? 1 : 0
            enabled: messageHover.hovered

            Behavior on opacity {
                animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
            }

            RowLayout {
                id: controlsRow
                x: root.isUser ? (parent.width - width) : 0
                spacing: 2


                AiMessageControlButton {
                    id: regenButton
                    accessibleName: Translation.tr("Regenerate response")
                    buttonIcon: "refresh"
                    visible: root.isAssistant
                    onClicked: Ai.regenerate(root.messageIndex)
                    StyledToolTip {
                        text: Translation.tr("Regenerate")
                    }
                }

                AiMessageControlButton {
                    id: copyButton
                    accessibleName: Translation.tr("Copy message")
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = root.messageData?.content
                        copyButton.activated = true
                        copyIconTimer.restart()
                    }
                    Timer {
                        id: copyIconTimer
                        interval: 1500
                        repeat: false
                        onTriggered: copyButton.activated = false
                    }
                    StyledToolTip {
                        text: Translation.tr("Copy")
                    }
                }

                AiMessageControlButton {
                    id: editButton
                    accessibleName: root.editing ? Translation.tr("Save message") : Translation.tr("Edit message")
                    activated: root.editing
                    enabled: root.messageData?.done ?? false
                    buttonIcon: "edit"
                    onClicked: {
                        root.editing = !root.editing
                        if (!root.editing) { // Save changes
                            root.saveMessage()
                        }
                    }
                    StyledToolTip {
                        text: root.editing ? Translation.tr("Save") : Translation.tr("Edit")
                    }
                }

                AiMessageControlButton {
                    id: toggleMarkdownButton
                    accessibleName: Translation.tr("View Markdown source")
                    activated: !root.renderMarkdown
                    buttonIcon: "code"
                    onClicked: root.renderMarkdown = !root.renderMarkdown
                    StyledToolTip {
                        text: Translation.tr("View Markdown source")
                    }
                }

                AiMessageControlButton {
                    id: deleteButton
                    accessibleName: Translation.tr("Delete message")
                    buttonIcon: "close"
                    onClicked: Ai.removeMessage(root.messageIndex)
                    StyledToolTip {
                        text: Translation.tr("Delete")
                    }
                }

                StyledText {
                    visible: (root.messageData?.timestamp ?? 0) > 0
                    Layout.alignment: Qt.AlignVCenter
                    Layout.leftMargin: 4
                    font.pixelSize: Appearance.font.pixelSize.smallie
                    color: Appearance.colors.colSubtext
                    text: {
                        if (!((root.messageData?.timestamp ?? 0) > 0)) return "";
                        const time = Qt.formatTime(new Date(root.messageData.timestamp), "hh:mm");
                        const modelId = root.messageData?.model ?? "";
                        const modelName = Ai.models[modelId]?.name ?? modelId;
                        return (root.isAssistant && modelName.length > 0) ? time + " · " + modelName : time;
                    }
                }
            }
        }
    }
}
