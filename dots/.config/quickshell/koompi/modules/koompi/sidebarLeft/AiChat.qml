import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft.aiChat
import qs.modules.koompi.sidebarLeft.aiChat.composer
import QtQuick
import QtQuick.Layouts

// The chat tab: a transcript over a composer, with the command table, its
// completion, the context meter and the recall strip between them. The
// transcript and the composer never name each other; this file wires them.
Item {
    id: root
    property real padding: 4
    property string commandPrefix: "/"

    onFocusChanged: focus => {
        if (focus) {
            composer.focusInput();
        }
    }

    Keys.onPressed: event => {
        // Tab and Backtab move focus. Grabbing them here is what kept the
        // transcript unreachable from the keyboard.
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            return;
        composer.focusInput();
        // Re-insert the keystroke that triggered focus (skip control chars like Esc/Enter)
        if (event.text.length > 0 && (event.modifiers & ~Qt.ShiftModifier) === 0 && event.text.charCodeAt(0) >= 0x20) {
            composer.insertText(event.text);
            event.accepted = true;
        }
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                transcript.pageUp();
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                transcript.pageDown();
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            Ai.clearMessages();
        }
    }

    // A slash line goes to the command table, anything else to the model.
    function submit(inputText) {
        recallStrip.reset();
        if (inputText.startsWith(root.commandPrefix)) {
            const words = inputText.split(" ");
            const command = words[0].substring(1);
            if (!commandTable.run(command, words.slice(1)))
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
        } else {
            Ai.sendUserMessage(inputText);
        }
        // Always scroll to bottom when user sends a message
        Qt.callLater(transcript.positionAtEnd);
    }

    ChatCommands {
        id: commandTable
        prefix: root.commandPrefix
        onModelPickerRequested: composer.modelPickerShown = true
    }

    CommandCompletion {
        id: completionSource
        commands: commandTable
    }

    // While the picker is open, a press anywhere else closes it and stops there,
    // the way a popup swallows the click that dismisses it.
    MouseArea {
        id: outsidePicker
        anchors.fill: parent
        z: 1
        visible: composer.modelPickerShown
        acceptedButtons: Qt.AllButtons
        onPressed: mouse => {
            const point = outsidePicker.mapToItem(modelPicker, mouse.x, mouse.y);
            if (modelPicker.contains(Qt.point(point.x, point.y))) {
                mouse.accepted = false;
                return;
            }
            modelPicker.dismissed();
        }
    }

    ColumnLayout {
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        ChatTranscript {
            id: transcript
            Layout.fillWidth: true
            Layout.fillHeight: true
            padding: root.padding
            composerEmpty: composer.text.length === 0
            messageInputField: composer
            onStarterChosen: text => {
                composer.text = "";
                composer.submit(text);
            }
            onModelPickerRequested: composer.modelPickerShown = true
            onKeyRequested: composer.prefill(root.commandPrefix + "key ")
            onComposerFocusRequested: composer.focusInput()
        }

        ContextMeter {
            Layout.fillWidth: true
            spacing: root.padding
        }

        RecallStrip {
            id: recallStrip
            Layout.fillWidth: true
            prefix: root.commandPrefix
        }

        RowLayout { // Undo-clear bar
            visible: Ai.canUndoClear
            Layout.alignment: Qt.AlignHCenter
            spacing: 5

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.colors.colSubtext
                text: Translation.tr("Chat cleared")
            }
            ApiCommandButton {
                buttonText: Translation.tr("Undo")
                onClicked: Ai.undoClear()
            }
        }

        KeyboardHelpSheet {
            Layout.fillWidth: true
            shown: composer.helpShown
            onDismissed: composer.helpShown = false
        }

        AttachMenu {
            id: attachMenu
            Layout.fillWidth: true
            visible: composer.attachMenuShown
            onVisibleChanged: if (visible) Qt.callLater(attachMenu.focusFirst)
            onInsertText: text => {
                composer.insertText(text);
                composer.attachMenuShown = false;
            }
            onAttachPath: path => {
                Ai.attachFile(path);
                composer.attachMenuShown = false;
            }
            onFilePathRequested: {
                composer.prefill(root.commandPrefix + "attach ");
                composer.attachMenuShown = false;
            }
        }

        ModelPicker {
            id: modelPicker
            Layout.fillWidth: true
            visible: composer.modelPickerShown
            onVisibleChanged: if (visible) Qt.callLater(modelPicker.focusFirst)
            models: Ai.modelList.map(id => ({
                id: id,
                name: Ai.models[id]?.name ?? id,
                description: Ai.models[id]?.description ?? ""
            }))
            currentId: Ai.currentModelId
            onPicked: id => {
                composer.modelPickerShown = false;
                Ai.setModel(id);
            }
            onDismissed: composer.modelPickerShown = false
        }

        ChatComposer {
            id: composer
            Layout.fillWidth: true
            padding: root.padding
            inputHeightLimit: root.height * 3 / 5
            prefix: root.commandPrefix
            completion: completionSource
            onTextChanged: recallStrip.noteTyping(composer.text)
            // However the picker closed (a pick, Escape, a click outside, the
            // chip again), typing carries on in the composer.
            onModelPickerShownChanged: if (!composer.modelPickerShown) composer.focusInput()
            onSubmitted: text => root.submit(text)
            onTranscriptFocusRequested: {
                if (!transcript.focusTranscript())
                    composer.focusNext();
            }
            onPageScrollRequested: dir => {
                if (dir === "up")
                    transcript.pageUp();
                else if (dir === "down")
                    transcript.pageDown();
                else if (dir === "home")
                    transcript.positionAtBeginning();
                else
                    transcript.positionAtEnd();
            }
            onRetryRequested: {
                Ai.retryRequest();
                transcript.stallDetected = false;
            }
        }
    }
}
