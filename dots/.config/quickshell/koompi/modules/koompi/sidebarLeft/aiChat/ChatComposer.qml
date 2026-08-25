import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.koompi.sidebarLeft
import qs.modules.koompi.sidebarLeft.aiChat.activity
import qs.modules.koompi.sidebarLeft.aiChat.composer
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// The input area: the text field and send button, the toolbar, the command
// palette, the help and attach sheets and the agent activity panel. What it
// needs from the transcript goes out as signals; it never reaches for an id.
ColumnLayout {
    id: root
    property real padding: 4
    property real inputHeightLimit: 0
    property string prefix: "/"
    property CommandCompletion completion: null
    readonly property var suggestionList: root.completion?.entries ?? []
    property alias text: messageInputField.text
    property bool helpShown: false
    property bool attachMenuShown: false
    property bool modelPickerShown: false
    readonly property bool suggestionsVisible: suggestions.visible

    signal submitted(string text)
    signal transcriptFocusRequested()
    signal pageScrollRequested(string dir) // "up", "down", "home" or "end"
    signal retryRequested()

    property var inputHistory: []
    property int historyCursor: -1
    property string historyDraft: ""

    function prefill(cmd) {
        messageInputField.text = cmd;
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    function insertText(text) {
        messageInputField.insert(messageInputField.cursorPosition, text);
        messageInputField.forceActiveFocus();
    }

    function focusInput() {
        messageInputField.forceActiveFocus();
    }

    // The Tab fallback when the transcript has nothing to focus.
    function focusNext() {
        messageInputField.nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason);
    }

    function recallHistory(step) {
        if (root.inputHistory.length === 0)
            return;
        if (root.historyCursor === -1)
            root.historyDraft = messageInputField.text;
        const next = Math.min(root.inputHistory.length - 1, Math.max(-1, root.historyCursor + step));
        root.historyCursor = next;
        messageInputField.text = next === -1 ? root.historyDraft : root.inputHistory[root.inputHistory.length - 1 - next];
        messageInputField.cursorPosition = messageInputField.text.length;
    }

    // Records the line in the history, then hands it out as `submitted`.
    function submit(inputText) {
        root.historyCursor = -1;
        root.historyDraft = "";
        if (inputText.trim().length > 0 && root.inputHistory[root.inputHistory.length - 1] !== inputText) {
            root.inputHistory = root.inputHistory.concat([inputText]).slice(-50);
        }
        root.submitted(inputText);
    }

    Process {
        id: decodeImageAndAttachProc
        property string imageDecodePath: Directories.cliphistDecode
        property string imageDecodeFileName: "image"
        property string imageDecodeFilePath: `${imageDecodePath}/${imageDecodeFileName}`
        function handleEntry(entry: string) {
            imageDecodeFileName = parseInt(entry.match(/^(\d+)\t/)[1]);
            decodeImageAndAttachProc.exec(["bash", "-c", `[ -f ${imageDecodeFilePath} ] || echo '${StringUtils.shellSingleQuoteEscape(entry)}' | ${Cliphist.cliphistBinary} decode > '${imageDecodeFilePath}'`]);
        }
        onExited: exitCode => {
            if (exitCode === 0) Ai.attachFile(imageDecodeFilePath);
            else console.error("[AiChat] Failed to decode image in clipboard content");
        }
    }

    DescriptionBox {
        text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
        showArrows: root.suggestionList.length > 1
    }

    CommandPalette { // Suggestions
        id: suggestions
        visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
        Layout.fillWidth: true
        entries: root.suggestionList
        onAccepted: value => suggestions.acceptSuggestion(value)

        onEntriesChanged: suggestions.selectedIndex = 0

        // The suggestion replaces the word being typed and the caret follows it.
        function acceptSuggestion(word) {
            const words = messageInputField.text.trim().split(/\s+/);
            words[Math.max(0, words.length - 1)] = word;
            root.prefill(words.join(" ") + " ");
        }

        function acceptSelectedWord() {
            if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < root.suggestionList.length)
                suggestions.acceptSuggestion(root.suggestionList[suggestions.selectedIndex].value);
        }
    }

    AgentActivityPanel { Layout.fillWidth: true } // the agent while it works, above the input

    component ToolbarIcon: MaterialSymbol {
        horizontalAlignment: Text.AlignHCenter
        iconSize: Appearance.font.pixelSize.larger
        color: Appearance.m3colors.m3onSurface
    }

    Rectangle { // Input area
        id: inputWrapper
        property real spacing: 5
        Layout.fillWidth: true
        radius: Appearance.rounding.normal - root.padding
        color: Appearance.colors.colLayer2
        implicitHeight: Math.max(inputFieldRowLayout.implicitHeight + inputFieldRowLayout.anchors.topMargin + commandButtonsRow.implicitHeight + commandButtonsRow.anchors.bottomMargin + spacing, 45) + (attachedFileIndicator.implicitHeight + spacing + attachedFileIndicator.anchors.topMargin)
        clip: true

        Behavior on implicitHeight {
            animation: Appearance.animation.elementMove.numberAnimation.createObject(this)
        }

        AttachedFileIndicator {
            id: attachedFileIndicator
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
                margins: visible ? 5 : 0
            }
            filePath: Ai.pendingFilePath
            onRemove: Ai.attachFile("")
        }

        RowLayout { // Input field and send button
            id: inputFieldRowLayout
            anchors {
                bottom: commandButtonsRow.top
                left: parent.left
                right: parent.right
                bottomMargin: 5
            }
            spacing: 0

            ScrollView {
                id: inputScrollView
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(root.inputHeightLimit, messageInputField.height)
                clip: true
                ScrollBar.vertical.policy: ScrollBar.AsNeeded

                StyledTextArea { // The actual TextArea (inside ScrollView to enable scrolling)
                    id: messageInputField
                    anchors.fill: parent
                    wrapMode: TextArea.Wrap
                    padding: 10
                    color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                    placeholderText: Ai.toolStatusLabel.length > 0
                        ? Ai.toolStatusLabel
                        : Translation.tr('Message the model... "%1" for commands').arg(root.prefix)

                    background: null

                    onTextChanged: root.completion?.updateSuggestions(messageInputField.text)

                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Tab && suggestions.visible) {
                            suggestions.acceptSelectedWord();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Tab) {
                            // A TextArea consumes Tab, so the focus chain has to be
                            // walked by hand or the composer is a keyboard trap.
                            root.transcriptFocusRequested();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_F1) {
                            root.helpShown = !root.helpShown;
                            event.accepted = true;
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_K) {
                            root.prefill(root.prefix);
                            event.accepted = true;
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
                            root.retryRequested();
                            event.accepted = true;
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_End && messageInputField.text.length === 0) {
                            // Only with nothing typed: in a text field Ctrl+End is
                            // the caret's, and taking it would be a papercut.
                            root.pageScrollRequested("end");
                            event.accepted = true;
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Home && messageInputField.text.length === 0) {
                            root.pageScrollRequested("home");
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) && event.modifiers === Qt.NoModifier) {
                            root.pageScrollRequested(event.key === Qt.Key_PageUp ? "up" : "down");
                            event.accepted = true;
                        } else if ((event.modifiers & Qt.AltModifier) && (event.key === Qt.Key_Up || event.key === Qt.Key_Down)) {
                            root.recallHistory(event.key === Qt.Key_Up ? 1 : -1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && suggestions.visible) {
                            suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && suggestions.visible) {
                            suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Up && (messageInputField.text.length === 0 || root.historyCursor >= 0)) {
                            root.recallHistory(1);
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Down && root.historyCursor >= 0) {
                            root.recallHistory(-1);
                            event.accepted = true;
                        } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                            if (event.modifiers & Qt.ShiftModifier) {
                                messageInputField.insert(messageInputField.cursorPosition, "\n");
                                event.accepted = true;
                            } else {
                                const inputText = messageInputField.text;
                                messageInputField.clear();
                                root.submit(inputText);
                                event.accepted = true;
                            }
                        } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_V) {
                            // Intercept Ctrl+V to handle image/file pasting
                            if (event.modifiers & Qt.ShiftModifier) {
                                // Let Shift+Ctrl+V = plain paste
                                messageInputField.text += Quickshell.clipboardText;
                                event.accepted = true;
                                return;
                            }
                            const currentClipboardEntry = Cliphist.entries[0];
                            const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                            if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) { // an image
                                decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                event.accepted = true;
                                return;
                            } else if (cleanCliphistEntry.startsWith("file://")) {
                                const fileName = decodeURIComponent(cleanCliphistEntry);
                                Ai.attachFile(fileName);
                                event.accepted = true;
                                return;
                            }
                            event.accepted = false; // No image, let text pasting proceed
                        } else if (event.key === Qt.Key_Escape) {
                            // Esc: close a sheet > cancel request > detach file > propagate (close sidebar)
                            if (root.helpShown || root.attachMenuShown || root.modelPickerShown) {
                                root.helpShown = false;
                                root.attachMenuShown = false;
                                root.modelPickerShown = false;
                                event.accepted = true;
                            } else if (Ai.requestActive) {
                                Ai.cancelRequest();
                                event.accepted = true;
                            } else if (Ai.pendingFilePath.length > 0) {
                                Ai.attachFile("");
                                event.accepted = true;
                            } else {
                                event.accepted = false;
                            }
                        }
                    }
                }
            }
            RippleButton { // Send button
                id: sendButton
                Layout.alignment: Qt.AlignBottom
                Layout.rightMargin: 5
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.small
                enabled: Ai.requestActive || messageInputField.text.length > 0
                toggled: enabled
                Accessible.name: Ai.requestActive ? Translation.tr("Stop response") : Translation.tr("Send message")

                MouseArea {
                    anchors.fill: parent
                    cursorShape: sendButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: {
                        if (Ai.requestActive) {
                            Ai.cancelRequest();
                            return;
                        }
                        const inputText = messageInputField.text;
                        root.submit(inputText);
                        messageInputField.clear();
                    }
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    iconSize: 22
                    color: sendButton.enabled ? Appearance.m3colors.m3onPrimary : Appearance.colors.colOnLayer2Disabled
                    text: Ai.requestActive ? "stop" : "arrow_upward"
                }
            }
        }

        RowLayout { // Controls
            id: commandButtonsRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 5
            anchors.leftMargin: 10
            anchors.rightMargin: 5
            spacing: 4

            ApiInputBoxIndicator {
                // Model indicator
                icon: "api"
                text: Ai.getModel().name
                tooltipText: Translation.tr("Answering: %1\nClick to switch model").arg(Ai.getModel().name)
                onClickedAction: () => root.modelPickerShown = !root.modelPickerShown
            }

            ApiInputBoxIndicator {
                // Tool indicator
                icon: "service_toolbox"
                text: Ai.currentTool.charAt(0).toUpperCase() + Ai.currentTool.slice(1)
                tooltipText: Translation.tr("Current tool: %1\nSet it with %2tool TOOL").arg(Ai.currentTool).arg(root.prefix)
                onClickedAction: () => root.prefill(root.prefix + "tool ")
            }

            ApiCommandButton {
                // Attach button
                colBackground: root.attachMenuShown ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2
                contentItem: ToolbarIcon { text: "attach_file" }
                onClicked: root.attachMenuShown = !root.attachMenuShown
                Accessible.name: Translation.tr("Attach")

                StyledToolTip { text: Translation.tr("A screenshot, the selection, this window, or a file") }
            }

            ApiCommandButton {
                // Keyboard help
                colBackground: root.helpShown ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2
                contentItem: ToolbarIcon { text: "keyboard" }
                onClicked: root.helpShown = !root.helpShown
                Accessible.name: Translation.tr("Keyboard shortcuts")

                StyledToolTip { text: Translation.tr("Keys — F1") }
            }

            ApiCommandButton {
                // Hand the conversation to the full window
                contentItem: ToolbarIcon { text: "open_in_full" }
                onClicked: GlobalStates.intelligenceOpen = true
                Accessible.name: Translation.tr("Open the full window")

                StyledToolTip { text: Translation.tr("Threads, memory and activity, in a window") }
            }

            Item {
                Layout.fillWidth: true
            }

            ButtonGroup {
                // Command buttons
                padding: 0

                ApiCommandButton {
                    buttonText: root.prefix
                    Accessible.name: Translation.tr("Commands")
                    StyledToolTip { text: Translation.tr("Commands — Ctrl+K") }
                    downAction: () => root.prefill(root.prefix)
                }
                ApiCommandButton {
                    buttonText: `${root.prefix}clear`
                    downAction: () => {
                        messageInputField.text = "";
                        root.submit(`${root.prefix}clear`);
                    }
                }
            }
        }
    }
}
