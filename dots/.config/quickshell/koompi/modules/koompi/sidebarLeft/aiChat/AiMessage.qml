import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import "grounding.js" as Grounding

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

    // A tool result is a role, not a flag. Whatever `visibleToUser` says, a
    // message carrying a tool result can never reach the assistant bubble: it is
    // the model's plumbing and the user reads a bubble as an answer. D22.
    property bool isToolResult: messageData?.role == 'tool'
        || (messageData?.toolCallId ?? "").length > 0
        || (messageData?.functionResponse ?? "").length > 0

    property bool isUser: messageData?.role == 'user' && !isToolResult
    property bool isInterface: messageData?.role == 'interface' && !isToolResult
    property bool isAssistant: messageData?.role == 'assistant' && !isToolResult

    readonly property var sources: root.isAssistant ? (messageData?.sources ?? []) : []
    readonly property var toolCalls: root.isAssistant ? (messageData?.toolCalls ?? []) : []
    readonly property var grounding: (root.isAssistant && (root.messageData?.done ?? false))
        ? Grounding.computeGrounding(root.sources, root.messageData?.content ?? "")
        : null
    readonly property bool usedAgent: root.sources.some(s => s?.type === "agent")
        || root.toolCalls.some(c => c?.name === "ask_agent")

    // The assistant turn that asked for this result, found by id rather than by
    // position, so a queued or retried turn cannot mis-pair them.
    readonly property var callingMessage: {
        const id = root.messageData?.toolCallId ?? "";
        if (!root.isToolResult || id.length === 0) return null;
        const ids = Ai.messageIDs ?? [];
        for (let i = ids.length - 1; i >= 0; i--) {
            const message = Ai.messageByID[ids[i]];
            for (const call of (message?.toolCalls ?? [])) {
                if (call?.id === id) return { message: message, call: call };
            }
        }
        return null;
    }
    readonly property real toolElapsedMs: {
        const start = root.callingMessage?.message?.timestamp ?? 0;
        const end = root.messageData?.timestamp ?? 0;
        return (start > 0 && end > start) ? (end - start) : -1;
    }
    readonly property string toolArguments: {
        const args = root.callingMessage?.call?.arguments;
        if (args === undefined || args === null) return "";
        return (typeof args === "string") ? args : JSON.stringify(args);
    }

    property list<var> messageBlocks: []

    // A think or code block shrink-wraps its own header rather than its body, so
    // letting it drive the bubble width squeezes the text into a narrow column.
    readonly property bool hasFullWidthBlock: messageBlocks.some(b => b.type === "think" || b.type === "code")

    // Nothing but the thinking pulse yet, so the bubble would be a coloured box
    // around it. Keyed on the content itself, not on the throttled block parse,
    // so the pulse stops on the first token rather than 120 ms after it.
    readonly property bool loadingOnly: ((messageData?.content ?? "").length === 0)
        && !(messageData?.done ?? false)

    anchors.left: parent?.left
    anchors.right: parent?.right
    implicitHeight: outerColumn.implicitHeight

    activeFocusOnTab: true
    Accessible.role: Accessible.Paragraph
    Accessible.name: root.isToolResult
        ? Translation.tr("Tool activity: %1").arg(root.messageData?.functionName ?? "")
        : Translation.tr("%1 message").arg(root.isUser ? Translation.tr("Your") : Translation.tr("Assistant"))

    component MessageBlock: QtObject {
        property string type: "text"
        property string content: ""
        property string lang: ""
        property bool completed: false
    }

    Component {
        id: messageBlockComponent
        MessageBlock {}
    }

    // Streaming reparses the whole message on every chunk. Handing ScriptModel a
    // fresh array each time destroyed every delegate and restarted the text
    // fade-in from zero, which is what read as flicker. Mutate the blocks that
    // are still the same kind and only rebuild the list when its shape changes.
    function recomputeBlocks() {
        const parsed = StringUtils.splitMarkdownBlocks(root.messageData?.content) ?? []
        const blocks = root.messageBlocks.slice()
        let shapeChanged = blocks.length !== parsed.length

        for (let i = 0; i < parsed.length; i++) {
            const source = parsed[i]
            const values = {
                type: source.type,
                content: source.content ?? "",
                lang: source.lang ?? "",
                completed: source.completed ?? false
            }
            // A block that changed kind needs its delegate swapped, so give the
            // row a new object rather than mutating the old one.
            if (i < blocks.length && blocks[i].type === values.type) {
                const block = blocks[i]
                if (block.content !== values.content) block.content = values.content
                if (block.lang !== values.lang) block.lang = values.lang
                if (block.completed !== values.completed) block.completed = values.completed
                continue
            }
            if (i < blocks.length) blocks[i].destroy()
            blocks[i] = messageBlockComponent.createObject(root, values)
            shapeChanged = true
        }

        for (let i = parsed.length; i < blocks.length; i++) blocks[i].destroy()
        blocks.length = parsed.length

        if (shapeChanged) root.messageBlocks = blocks
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

        Loader { // Tool plumbing renders as an activity row, never as a message
            Layout.fillWidth: true
            active: root.isToolResult
            visible: active
            sourceComponent: ToolActivityRow {
                functionName: root.messageData?.functionName ?? Translation.tr("tool")
                response: root.messageData?.functionResponse ?? ""
                arguments: root.toolArguments
                elapsedMs: root.toolElapsedMs
            }
        }

        Loader { // Bubble row (aligns the bubble left/right)
            Layout.fillWidth: true
            active: !root.isToolResult
            visible: active
            sourceComponent: bubbleRowComponent
        }

        Loader {
            Layout.fillWidth: true
            sourceComponent: controlsRowComponent
        }
    }

    Component {
        id: bubbleRowComponent

        Item {
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
                    visible: root.isAssistant && !root.loadingOnly
                    anchors.centerIn: parent
                    width: root.avatarSize * 0.7
                    height: root.avatarSize * 0.7
                    source: "koompi-symbolic.svg"
                    colorize: true
                    color: Appearance.colors.colOnLayer1
                }

                ThinkingIndicator { // takes the logo's place until the first token
                    visible: root.isAssistant && root.loadingOnly
                    anchors.centerIn: parent
                    active: visible
                }
            }

            Rectangle {
                id: bubble
                y: 0
                x: root.isUser ? (parent.width - width - root.avatarSpace) : root.avatarSpace
                radius: Appearance.rounding.normal
                color: root.isUser ? Appearance.colors.colLayer2
                    : (root.isInterface || root.loadingOnly) ? "transparent"
                    : Appearance.colors.colLayer1
                implicitHeight: contentColumn.implicitHeight + root.messagePadding * 2
                readonly property real maxWidth: (parent.width - root.avatarSpace)
                    * (root.isUser ? 0.88 : root.isInterface ? 1.0 : 0.96)
                // A wrapped TextArea reports an implicitWidth derived from the width the
                // layout just gave it, so shrink-wrapping a markdown reply collapses it to
                // one word per line. Only the user's own short bubbles shrink to fit.
                width: (root.hasFullWidthBlock || (!root.isUser && !root.loadingOnly))
                    ? maxWidth
                    : Math.min(contentColumn.implicitWidth + root.messagePadding * 2, maxWidth)

                ColumnLayout {
                    id: contentColumn
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: root.messagePadding
                    spacing: root.contentSpacing

                    Loader {
                        Layout.fillWidth: true
                        Layout.bottomMargin: active ? 4 : 0
                        // A turn that only dispatched a tool claims nothing, so it
                        // gets no grounding header to claim it with.
                        active: root.isAssistant && (root.messageData?.done ?? false)
                            && (root.messageData?.content ?? "").trim().length > 0
                        visible: active
                        sourceComponent: MessageGroundingHeader {
                            modelId: root.messageData?.model ?? ""
                            usedAgent: root.usedAgent
                            grounding: root.grounding
                        }
                    }

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
                                    sources: root.sources
                                    onSourceActivated: index => citations.highlight(index)
                                } }
                            }
                        }
                    }

                    Repeater { // What this turn asked a tool to do, read off the call itself
                        model: ScriptModel {
                            values: root.toolCalls
                        }

                        RowLayout {
                            id: toolCallRow
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 5

                            MaterialSymbol {
                                text: "arrow_outward"
                                iconSize: Appearance.font.pixelSize.smallie
                                color: Appearance.colors.colSubtext
                            }

                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                font.pixelSize: Appearance.font.pixelSize.smallest
                                font.family: Appearance.font.family.monospace
                                color: Appearance.colors.colSubtext
                                text: {
                                    const args = toolCallRow.modelData?.arguments;
                                    const rendered = (args === undefined || args === null) ? ""
                                        : (typeof args === "string" ? args : JSON.stringify(args));
                                    return Translation.tr("called %1 %2").arg(toolCallRow.modelData?.name ?? "").arg(rendered);
                                }
                            }
                        }
                    }

                    MessageCitations {
                        id: citations
                        Layout.fillWidth: true
                        sources: root.sources
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
    }

    Component {
        id: controlsRowComponent

        // Revealed on hover, and on keyboard focus: a control that only a mouse
        // can find is a control half the users do not have. D29.
        // A FocusScope, because `activeFocus` on a plain Item is only true when
        // that exact item holds focus, never when one of its buttons does.
        FocusScope {
            id: controlsContainer
            readonly property bool revealed: messageHover.hovered || controlsContainer.activeFocus || root.activeFocus
            implicitHeight: controlsRow.implicitHeight
            opacity: revealed ? 1 : 0

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
                    id: wrongButton
                    accessibleName: Translation.tr("This is wrong")
                    buttonIcon: "flag"
                    visible: root.isAssistant
                    onClicked: Ai.openCorrection({
                        "claim": (root.messageData?.content ?? "").split("\n")[0],
                        "messageId": Ai.idForMessage(root.messageData),
                        "source": null
                    })
                    StyledToolTip { text: Translation.tr("Tell me the right fact") }
                }

                AiMessageControlButton {
                    id: copyButton
                    accessibleName: root.isToolResult ? Translation.tr("Copy tool output") : Translation.tr("Copy message")
                    buttonIcon: activated ? "inventory" : "content_copy"
                    onClicked: {
                        Quickshell.clipboardText = root.isToolResult
                            ? (root.messageData?.functionResponse ?? "")
                            : (root.messageData?.content ?? "")
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
                    visible: !root.isToolResult
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
                    visible: !root.isToolResult
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
