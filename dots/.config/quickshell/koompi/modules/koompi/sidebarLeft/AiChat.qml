import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.koompi.sidebarLeft.aiChat
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io

Item {
    id: root
    property real padding: 4
    property var inputField: messageInputField
    property string commandPrefix: "/"

    property var suggestionQuery: ""
    property var suggestionList: []

    onFocusChanged: focus => {
        if (focus) {
            root.inputField.forceActiveFocus();
        }
    }

    Keys.onPressed: event => {
        messageInputField.forceActiveFocus();
        // Re-insert the keystroke that triggered focus (skip control chars like Esc/Enter)
        if (event.text.length > 0 && (event.modifiers & ~Qt.ShiftModifier) === 0 && event.text.charCodeAt(0) >= 0x20) {
            messageInputField.insert(messageInputField.cursorPosition, event.text);
            event.accepted = true;
        }
        if (event.modifiers === Qt.NoModifier) {
            if (event.key === Qt.Key_PageUp) {
                messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                event.accepted = true;
            } else if (event.key === Qt.Key_PageDown) {
                messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                event.accepted = true;
            }
        }
        if ((event.modifiers & Qt.ControlModifier) && (event.modifiers & Qt.ShiftModifier) && event.key === Qt.Key_O) {
            Ai.clearMessages();
        }
    }

    property var allCommands: [
        {
            name: "attach",
            description: Translation.tr("Attach a file. Only works with Gemini."),
            execute: args => {
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "model",
            description: Translation.tr("Choose model"),
            execute: args => {
                Ai.setModel(args[0]);
            }
        },
        {
            name: "tool",
            description: Translation.tr("Set the tool to use for the model."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                } else {
                    const tool = args[0];
                    const switched = Ai.setTool(tool);
                    if (switched) {
                        Ai.addMessage(Translation.tr("Tool set to: %1").arg(tool), Ai.interfaceRole);
                    }
                }
            }
        },
        {
            name: "prompt",
            description: Translation.tr("Set the system prompt for the model."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            description: Translation.tr("Set API key"),
            execute: args => {
                if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "endpoint",
            description: Translation.tr("Set or view model endpoint. Usage: /endpoint [remote|local] URL | /endpoint reset"),
            execute: args => {
                Ai.setEndpoint(args.join(" ").trim());
            }
        },
        {
            name: "save",
            description: Translation.tr("Save chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs);
            }
        },
        {
            name: "load",
            description: Translation.tr("Load chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.loadChat(joinedArgs);
            }
        },
        {
            name: "clear",
            description: Translation.tr("Clear chat history"),
            execute: () => {
                Ai.clearMessages();
            }
        },
        {
            name: "temp",
            description: Translation.tr("Set temperature (randomness) of the model. Values range between 0 to 2 for Gemini, 0 to 1 for other models. Default is 0.5."),
            execute: args => {
                // console.log(args)
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                } else {
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        {
            name: "owner",
            description: Translation.tr("Set the name the assistant should call you by."),
            execute: args => {
                const name = args.join(" ").trim();
                if (name.length === 0 || name === "get") {
                    const current = Persistent.states.ai.ownerName;
                    if (current.length > 0) {
                        Ai.addMessage(Translation.tr("You're registered as **%1**. Change it with %2owner NEW_NAME").arg(current).arg(root.commandPrefix), Ai.interfaceRole);
                    } else {
                        Ai.addMessage(Translation.tr("No owner name set yet. Register with %1owner YOUR_NAME").arg(root.commandPrefix), Ai.interfaceRole);
                    }
                    return;
                }
                Ai.setOwnerName(name);
                Ai.addMessage(Translation.tr("Got it — I'll call you **%1** from now on.").arg(name), Ai.interfaceRole);
            }
        },
        {
            name: "whoami",
            description: Translation.tr("Show who the assistant thinks you are."),
            execute: () => {
                const current = Persistent.states.ai.ownerName;
                const ownerLine = current.length > 0 ? current : Translation.tr("unknown (tell me your name or use %1owner)").arg(root.commandPrefix);
                Ai.addMessage(Translation.tr("**Assistant**: %1\n**Owner**: %2\n**Login user**: %3").arg(Ai.aiName).arg(ownerLine).arg(SystemInfo.username), Ai.interfaceRole);
            }
        },
        {
            name: "remember",
            description: Translation.tr("Manually store a fact in long-term memory."),
            execute: args => {
                const text = args.join(" ").trim();
                if (text.length === 0) {
                    Ai.addMessage(Translation.tr("Usage: %1remember SOMETHING TO REMEMBER").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                if (!MemoryService.ready) {
                    Ai.addMessage(Translation.tr("Memory service is not ready."), Ai.interfaceRole);
                    return;
                }
                MemoryService.remember(text, "fact", [], "user", resp => {
                    Ai.addMessage(resp && resp.ok
                        ? (resp.stored ? Translation.tr("Remembered: %1").arg(text) : Translation.tr("Already in memory."))
                        : Translation.tr("Failed to store memory."), Ai.interfaceRole);
                });
            }
        },
        {
            name: "memories",
            description: Translation.tr("List stored long-term memories."),
            execute: () => {
                if (!MemoryService.ready) {
                    Ai.addMessage(Translation.tr("Memory service is not ready."), Ai.interfaceRole);
                    return;
                }
                MemoryService.list(50, resp => {
                    const results = resp?.results ?? [];
                    if (results.length === 0) {
                        Ai.addMessage(Translation.tr("No memories stored yet."), Ai.interfaceRole);
                        return;
                    }
                    const lines = results.map(r => `- \`#${r.id}\` [${r.mtype}] ${r.text}`).join("\n");
                    Ai.addMessage(Translation.tr("**Stored memories** (forget with %1forget ID):\n%2").arg(root.commandPrefix).arg(lines), Ai.interfaceRole);
                });
            }
        },
        {
            name: "forget",
            description: Translation.tr("Forget a memory by id (see /memories)."),
            execute: args => {
                const id = parseInt(args[0]);
                if (isNaN(id)) {
                    Ai.addMessage(Translation.tr("Usage: %1forget MEMORY_ID").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                MemoryService.forget(id, resp => {
                    Ai.addMessage(resp && resp.ok && resp.forgotten
                        ? Translation.tr("Forgot memory #%1.").arg(id)
                        : Translation.tr("No memory with id #%1.").arg(id), Ai.interfaceRole);
                });
            }
        },
        {
            name: "compact",
            description: Translation.tr("Compact conversation context into a summary to preserve model quality."),
            execute: () => {
                if (!Ai.currentModelHasApiKey) {
                    Ai.addMessage(Translation.tr("No API key set — cannot compact."), Ai.interfaceRole);
                    return;
                }
                if (Ai.compacting) {
                    Ai.addMessage(Translation.tr("Already compacting."), Ai.interfaceRole);
                    return;
                }
                Ai.compact(null);
            }
        },
        {
            name: "fork",
            description: Translation.tr("Snapshot this session to memory. Resume later with /resume SESSION_ID."),
            execute: () => {
                if (!MemoryService.ready) {
                    Ai.addMessage(Translation.tr("Memory service not ready."), Ai.interfaceRole);
                    return;
                }
                const msgList = Ai.messageIDs.map(id => Ai.messageByID[id]).filter(m => m.role !== Ai.interfaceRole);
                if (msgList.length < 2) {
                    Ai.addMessage(Translation.tr("Not enough messages to fork."), Ai.interfaceRole);
                    return;
                }
                const summary = msgList.map(m => m.role.toUpperCase() + ": " + (m.rawContent ?? "")).join("\n\n---\n\n").substring(0, 4000);
                const forkText = "[Session fork " + Ai.sessionId + "]\n\n" + summary;
                MemoryService.remember(forkText, "compaction", ["session_fork", Ai.sessionId], "user", resp => {
                    Ai.addMessage(resp && resp.ok && resp.stored
                        ? Translation.tr("Session forked as **%1**. Resume with `/resume %1`").arg(Ai.sessionId)
                        : Translation.tr("Fork failed."), Ai.interfaceRole);
                });
            }
        },
        {
            name: "resume",
            description: Translation.tr("Restore a forked session. Usage: /resume SESSION_ID"),
            execute: args => {
                const forkId = (args[0] ?? "").trim();
                if (!forkId) {
                    Ai.addMessage(Translation.tr("Usage: %1resume SESSION_ID").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                if (!MemoryService.ready) {
                    Ai.addMessage(Translation.tr("Memory service not ready."), Ai.interfaceRole);
                    return;
                }
                MemoryService.recall("Session fork " + forkId, 5, results => {
                    const match = (results ?? []).find(r => (r.text ?? "").includes("[Session fork " + forkId + "]"));
                    if (!match) {
                        Ai.addMessage(Translation.tr("No session found with id **%1**.").arg(forkId), Ai.interfaceRole);
                        return;
                    }
                    Ai.clearMessages();
                    Ai.injectContext(match.text);
                    Ai.addMessage(Translation.tr("Session **%1** restored.").arg(forkId), Ai.interfaceRole);
                });
            }
        },
        {
            name: "research",
            description: Translation.tr("Deep research loop — Think, Search, Synthesize (max 5 iterations). Usage: /research QUERY"),
            execute: args => {
                const query = args.join(" ").trim();
                if (!query) {
                    Ai.addMessage(Translation.tr("Usage: %1research QUERY").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                ResearchService.start(query);
            }
        },
        {
            name: "task",
            description: Translation.tr("Run a subtask in a fresh context; result posted back here. Usage: /task DESCRIPTION"),
            execute: args => {
                const desc = args.join(" ").trim();
                if (!desc) {
                    Ai.addMessage(Translation.tr("Usage: %1task DESCRIPTION").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.spawnSubtask(desc);
            }
        },
        ...(Config.options?.ai?.debugCommands ?? false ? [{
            name: "test",
            description: Translation.tr("Markdown test"),
            execute: () => {
                Ai.addMessage(`
<think>
A longer think block to test revealing animation
OwO wem ipsum dowo sit amet, consekituwet awipiscing ewit, sed do eiuwsmod tempow inwididunt ut wabowe et dowo mawa. Ut enim ad minim weniam, quis nostwud exeucitation uwuwamcow bowowis nisi ut awiquip ex ea commowo consequat. Duuis aute iwuwe dowo in wepwependewit in wowuptate velit esse ciwwum dowo eu fugiat nuwa pawiatuw. Excepteuw sint occaecat cupidatat non pwowoident, sunt in cuwpa qui officia desewunt mowit anim id est wabowum. Meouw! >w<
Mowe uwu wem ipsum!
</think>
## ✏️ Markdown test
### Formatting

- *Italic*, \`Monospace\`, **Bold**, [Link](https://example.com)
- Arch lincox icon <img src="${Quickshell.shellPath("assets/icons/arch-symbolic.svg")}" height="${Appearance.font.pixelSize.small}"/>

### Table

Quickshell vs AGS/Astal

|                          | Quickshell       | AGS/Astal         |
|--------------------------|------------------|-------------------|
| UI Toolkit               | Qt               | Gtk3/Gtk4         |
| Language                 | QML              | Js/Ts/Lua         |
| Reactivity               | Implied          | Needs declaration |
| Widget placement         | Mildly difficult | More intuitive    |
| Bluetooth & Wifi support | ❌               | ✅                |
| No-delay keybinds        | ✅               | ❌                |
| Development              | New APIs         | New syntax        |

### Code block

Just a hello world...

\`\`\`cpp
#include <bits/stdc++.h>
// This is intentionally very long to test scrolling
const std::string GREETING = \"UwU\";
int main(int argc, char* argv[]) {
    std::cout << GREETING;
}
\`\`\`

### LaTeX


Inline w/ dollar signs: $\\frac{1}{2} = \\frac{2}{4}$

Inline w/ double dollar signs: $$\\int_0^\\infty e^{-x^2} dx = \\frac{\\sqrt{\\pi}}{2}$$

Inline w/ backslash and square brackets \\[\\int_0^\\infty \\frac{1}{x^2} dx = \\infty\\]

Inline w/ backslash and round brackets \\(e^{i\\pi} + 1 = 0\\)
`, Ai.interfaceRole);
            }
        }] : []),
    ]

    property bool stallDetected: false
    property var recallTypingResults: []
    property bool recallStripVisible: false
    property bool recallDismissed: false

    function prefillCommand(cmd) {
        messageInputField.text = cmd;
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    Timer {
        id: stallWatchdog
        interval: 60000
        repeat: false
        onTriggered: { if (Ai.requestActive) root.stallDetected = true }
    }

    Connections {
        target: Ai
        function onTokenStreamed() { stallWatchdog.restart(); root.stallDetected = false }
        function onResponseFinished() { stallWatchdog.stop(); root.stallDetected = false }
        function onRequestActiveChanged() {
            if (Ai.requestActive) { stallWatchdog.restart() }
            else { stallWatchdog.stop(); root.stallDetected = false }
        }
    }

    Timer {
        id: recallDebounceTimer
        interval: 600
        repeat: false
        onTriggered: {
            const text = messageInputField.text;
            if (text.length < 3 || text.startsWith(root.commandPrefix) || !MemoryService.ready) {
                root.recallTypingResults = [];
                root.recallStripVisible = false;
                return;
            }
            MemoryService.recall(text, 3, results => {
                root.recallTypingResults = results ?? [];
                root.recallStripVisible = !root.recallDismissed && root.recallTypingResults.length > 0;
            });
        }
    }

    function handleInput(inputText) {
        root.recallDismissed = false;
        if (inputText.startsWith(root.commandPrefix)) {
            // Handle special commands
            const command = inputText.split(" ")[0].substring(1);
            const args = inputText.split(" ").slice(1);
            const commandObj = root.allCommands.find(cmd => cmd.name === `${command}`);
            if (commandObj) {
                commandObj.execute(args);
            } else {
                Ai.addMessage(Translation.tr("Unknown command: ") + command, Ai.interfaceRole);
            }
        } else {
            Ai.sendUserMessage(inputText);
        }

        // Always scroll to bottom when user sends a message
        Qt.callLater(messageListView.positionViewAtEnd);
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
        onExited: (exitCode, exitStatus) => {
            if (exitCode === 0) {
                Ai.attachFile(imageDecodeFilePath);
            } else {
                console.error("[AiChat] Failed to decode image in clipboard content");
            }
        }
    }

    component StatusItem: MouseArea {
        id: statusItem
        property string icon
        property string statusText
        property string description
        property var clickAction: null
        hoverEnabled: true
        cursorShape: clickAction ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (clickAction) clickAction()
        implicitHeight: statusItemRowLayout.implicitHeight
        implicitWidth: statusItemRowLayout.implicitWidth

        RowLayout {
            id: statusItemRowLayout
            spacing: 0
            MaterialSymbol {
                text: statusItem.icon
                iconSize: Appearance.font.pixelSize.huge
                color: Appearance.colors.colSubtext
            }
            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                text: statusItem.statusText
                color: Appearance.colors.colSubtext
                animateChange: true
            }
        }

        StyledToolTip {
            text: statusItem.description
            extraVisibleCondition: false
            alternativeVisibleCondition: statusItem.containsMouse
        }
    }

    component StatusSeparator: Rectangle {
        implicitWidth: 4
        implicitHeight: 4
        radius: implicitWidth / 2
        color: Appearance.colors.colOutlineVariant
    }

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item {
            // Messages
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: swipeView.width
                    height: swipeView.height
                    radius: Appearance.rounding.small
                }
            }

            StyledRectangularShadow {
                z: 1
                target: statusBg
                opacity: messageListView.atYBeginning ? 0 : 1
                visible: opacity > 0
                Behavior on opacity {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
            }
            Rectangle {
                id: statusBg
                z: 2
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    top: parent.top
                    topMargin: 4
                }
                implicitWidth: statusRowLayout.implicitWidth + 10 * 2
                implicitHeight: Math.max(statusRowLayout.implicitHeight, 38)
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                RowLayout {
                    id: statusRowLayout
                    anchors.centerIn: parent
                    spacing: 10

                    StatusItem {
                        icon: Ai.currentModelHasApiKey ? "key" : "key_off"
                        statusText: ""
                        description: Ai.currentModelHasApiKey ? Translation.tr("API key is set\nChange with /key YOUR_API_KEY") : Translation.tr("No API key\nSet it with /key YOUR_API_KEY")
                        clickAction: () => root.prefillCommand(root.commandPrefix + "key ")
                    }
                    StatusSeparator {}
                    StatusItem {
                        icon: "device_thermostat"
                        statusText: Ai.temperature.toFixed(1)
                        description: Translation.tr("Temperature\nChange with /temp VALUE")
                        clickAction: () => root.prefillCommand(root.commandPrefix + "temp ")
                    }
                    StatusSeparator {
                        visible: Ai.tokenCount.total > 0
                    }
                    StatusItem {
                        visible: Ai.tokenCount.total > 0
                        icon: "token"
                        statusText: Ai.tokenCount.total
                        description: Translation.tr("Total token count\nInput: %1\nOutput: %2").arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
                    }
                }
            }

            ScrollEdgeFade {
                z: 1
                target: messageListView
                vertical: true
            }

            StyledListView { // Message list
                id: messageListView
                z: 0
                anchors.fill: parent
                spacing: 10
                popin: false
                topMargin: statusBg.implicitHeight + statusBg.anchors.topMargin * 2
                scrollAnimation: false

                touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
                mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

                property int lastResponseLength: 0
                // A new message (user or AI) always jumps the view to the newest one,
                // so the user never has to scroll down to see the latest chat.
                onCountChanged: Qt.callLater(positionViewAtEnd)
                // While a response streams in, keep the bottom pinned — but only if the
                // user is already at the bottom, so scrolling up to read isn't yanked back.
                onContentHeightChanged: {
                    if (atYEnd)
                        Qt.callLater(positionViewAtEnd);
                }

                add: null // Prevent function calls from being janky

                model: ScriptModel {
                    values: Ai.messageIDs.filter(id => {
                        const message = Ai.messageByID[id];
                        return message?.visibleToUser ?? true;
                    })
                }
                delegate: AiMessage {
                    required property var modelData
                    required property int index
                    messageIndex: index
                    messageData: Ai.messageByID[modelData]
                    messageInputField: root.inputField
                }
            }

            PagePlaceholder {
                z: 2
                shown: Ai.messageIDs.length === 0
                icon: "neurology"
                title: Translation.tr("Large language models")
                description: Translation.tr("Type /key to get started with online models\nCtrl+O to expand sidebar\nCtrl+P to pin sidebar\nCtrl+D to detach sidebar")
                shape: MaterialShape.Shape.PixelCircle
            }

            RowLayout { // Empty-state starter chips
                z: 2
                visible: Ai.messageIDs.length === 0
                anchors {
                    horizontalCenter: parent.horizontalCenter
                    bottom: parent.bottom
                    bottomMargin: 20
                }
                spacing: 5

                ApiCommandButton {
                    visible: !Ai.currentModelHasApiKey
                    buttonText: Translation.tr("Set API key")
                    onClicked: root.prefillCommand(root.commandPrefix + "key ")
                }
                ApiCommandButton {
                    buttonText: Translation.tr("Pick model")
                    onClicked: root.prefillCommand(root.commandPrefix + "model ")
                }
                ApiCommandButton {
                    visible: Ai.savedChats.length > 0
                    buttonText: Translation.tr("Load chat")
                    onClicked: root.prefillCommand(root.commandPrefix + "load ")
                }
            }

            ScrollToBottomButton {
                z: 3
                target: messageListView
            }
        }

        // Token HUD — thin context fill bar (#14)
        Rectangle {
            visible: Ai.tokenCount.total > 0
            Layout.fillWidth: true
            height: 3
            radius: 1
            color: Appearance.colors.colLayer1
            Rectangle {
                readonly property real fill: Ai.tokenCount.total / Math.max(1, Config.options?.ai?.memory?.contextWindow ?? 128000)
                width: parent.width * Math.min(1.0, fill)
                height: parent.height
                radius: parent.radius
                color: fill >= 0.85 ? Appearance.colors.colError
                     : fill >= 0.60 ? Appearance.m3colors.m3tertiary
                     : Appearance.colors.colPrimary
                Behavior on width {
                    animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                }
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
            }
            MouseArea {
                id: contextBarMouseArea
                anchors.fill: parent
                anchors.topMargin: -4
                anchors.bottomMargin: -4
                hoverEnabled: true
                acceptedButtons: Qt.NoButton

                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: contextBarMouseArea.containsMouse
                    text: Translation.tr("Context: %1 / %2 tokens\nInput: %3 — Output: %4").arg(Ai.tokenCount.total).arg(Config.options?.ai?.memory?.contextWindow ?? 128000).arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
                }
            }
        }
        StyledText {
            visible: Ai.tokenCount.total > 0
                && Ai.tokenCount.total >= (Config.options?.ai?.memory?.contextWindow ?? 128000) * 0.90
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            font.pixelSize: Appearance.font.pixelSize.small
            font.italic: true
            color: Appearance.colors.colError
            text: Translation.tr("Context nearly full — will compact soon")
        }

        DescriptionBox {
            text: root.suggestionList[suggestions.selectedIndex]?.description ?? ""
            showArrows: root.suggestionList.length > 1
        }

        RowLayout {
            visible: root.stallDetected
            Layout.alignment: Qt.AlignHCenter
            spacing: 5

            StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                font.italic: true
                color: Appearance.colors.colSubtext
                text: Translation.tr("Still thinking…")
            }
            ApiCommandButton {
                buttonText: Translation.tr("Retry")
                onClicked: {
                    Ai.retryRequest();
                    root.stallDetected = false;
                }
            }
            ApiCommandButton {
                buttonText: Translation.tr("Stop")
                onClicked: {
                    Ai.cancelRequest();
                    root.stallDetected = false;
                }
            }
        }

        FlowButtonGroup { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            property int selectedIndex: 0
            Layout.fillWidth: true
            spacing: 5

            Repeater {
                id: suggestionRepeater
                model: {
                    suggestions.selectedIndex = 0;
                    return root.suggestionList.slice(0, 10);
                }
                delegate: ApiCommandButton {
                    id: commandButton
                    colBackground: suggestions.selectedIndex === index ? Appearance.colors.colSecondaryContainerHover : Appearance.colors.colSecondaryContainer
                    bounce: false
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        horizontalAlignment: Text.AlignHCenter
                        text: modelData.displayName ?? modelData.name
                    }

                    onHoveredChanged: {
                        if (commandButton.hovered) {
                            suggestions.selectedIndex = index;
                        }
                    }
                    onClicked: {
                        suggestions.acceptSuggestion(modelData.name);
                    }
                }
            }

            function acceptSuggestion(word) {
                const words = messageInputField.text.trim().split(/\s+/);
                if (words.length > 0) {
                    words[words.length - 1] = word;
                } else {
                    words.push(word);
                }
                const updatedText = words.join(" ") + " ";
                messageInputField.text = updatedText;
                messageInputField.cursorPosition = messageInputField.text.length;
                messageInputField.forceActiveFocus();
            }

            function acceptSelectedWord() {
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < suggestionRepeater.count) {
                    const word = root.suggestionList[suggestions.selectedIndex].name;
                    suggestions.acceptSuggestion(word);
                }
            }
        }

        // Recall-while-typing strip (#13)
        ColumnLayout {
            visible: root.recallStripVisible
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                StyledText {
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: Translation.tr("Recalled:")
                }
                Item { Layout.fillWidth: true }
                ApiCommandButton {
                    contentItem: StyledText {
                        font.pixelSize: Appearance.font.pixelSize.small
                        color: Appearance.m3colors.m3onSurface
                        text: "×"
                    }
                    onClicked: {
                        root.recallStripVisible = false;
                        root.recallDismissed = true;
                    }
                }
            }
            Repeater {
                model: root.recallTypingResults.slice(0, 3)
                delegate: StyledText {
                    required property var modelData
                    Layout.fillWidth: true
                    font.pixelSize: Appearance.font.pixelSize.small
                    color: Appearance.colors.colSubtext
                    text: "• " + (modelData.text ?? "")
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }
            }
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
                    Layout.preferredHeight: Math.min(root.height * 3/5, messageInputField.height)
                    clip: true
                    ScrollBar.vertical.policy: ScrollBar.AsNeeded

                    StyledTextArea { // The actual TextArea (inside ScrollView to enable scrolling)
                        id: messageInputField
                        anchors.fill: parent
                        wrapMode: TextArea.Wrap
                        padding: 10
                        color: activeFocus ? Appearance.m3colors.m3onSurface : Appearance.m3colors.m3onSurfaceVariant
                        placeholderText: Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                        background: null

                        onTextChanged: {
                            // Handle suggestions
                            if (messageInputField.text.length === 0) {
                                root.suggestionQuery = "";
                                root.suggestionList = [];
                                root.recallDismissed = false;
                                return;
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}model`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const modelResults = Fuzzy.go(root.suggestionQuery, Ai.modelList.map(model => {
                                    return {
                                        name: Fuzzy.prepare(model),
                                        obj: model
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = modelResults.map(model => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "model ") : ""}${model.target}`,
                                        displayName: `${Ai.models[model.target].name}`,
                                        description: `${Ai.models[model.target].description}`
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}prompt`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.promptFiles.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "prompt ") : ""}${file.target}`,
                                        displayName: `${FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target))}`,
                                        description: Translation.tr("Load prompt from %1").arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}save`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "save ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr("Save chat to %1").arg(chatName)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}load`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const promptFileResults = Fuzzy.go(root.suggestionQuery, Ai.savedChats.map(file => {
                                    return {
                                        name: Fuzzy.prepare(file),
                                        obj: file
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = promptFileResults.map(file => {
                                    const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file.target)).trim();
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "load ") : ""}${chatName}`,
                                        displayName: `${chatName}`,
                                        description: Translation.tr(`Load chat from %1`).arg(file.target)
                                    };
                                });
                            } else if (messageInputField.text.startsWith(`${root.commandPrefix}tool`)) {
                                root.suggestionQuery = messageInputField.text.split(" ")[1] ?? "";
                                const toolResults = Fuzzy.go(root.suggestionQuery, Ai.availableTools.map(tool => {
                                    return {
                                        name: Fuzzy.prepare(tool),
                                        obj: tool
                                    };
                                }), {
                                    all: true,
                                    key: "name"
                                });
                                root.suggestionList = toolResults.map(tool => {
                                    const toolName = tool.target;
                                    return {
                                        name: `${messageInputField.text.trim().split(" ").length == 1 ? (root.commandPrefix + "tool ") : ""}${tool.target}`,
                                        displayName: toolName,
                                        description: Ai.toolDescriptions[toolName]
                                    };
                                });
                            } else if (messageInputField.text.startsWith(root.commandPrefix)) {
                                root.suggestionQuery = messageInputField.text;
                                root.suggestionList = root.allCommands.filter(cmd => cmd.name.startsWith(messageInputField.text.substring(1))).map(cmd => {
                                    return {
                                        name: `${root.commandPrefix}${cmd.name}`,
                                        description: `${cmd.description}`
                                    };
                                });
                            }
                            // Recall while typing — debounced (#13)
                            if (messageInputField.text.length >= 3 && !messageInputField.text.startsWith(root.commandPrefix)) {
                                recallDebounceTimer.restart();
                            } else {
                                recallDebounceTimer.stop();
                                root.recallTypingResults = [];
                                root.recallStripVisible = false;
                            }
                        }

                        function accept() {
                            root.handleInput(text);
                            text = "";
                        }

                        Keys.onPressed: event => {
                            if (event.key === Qt.Key_Tab && suggestions.visible) {
                                suggestions.acceptSelectedWord();
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) && event.modifiers === Qt.NoModifier) {
                                if (event.key === Qt.Key_PageUp) {
                                    messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                                } else {
                                    messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                                }
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Up && suggestions.visible) {
                                suggestions.selectedIndex = Math.max(0, suggestions.selectedIndex - 1);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_Down && suggestions.visible) {
                                suggestions.selectedIndex = Math.min(root.suggestionList.length - 1, suggestions.selectedIndex + 1);
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_Enter || event.key === Qt.Key_Return)) {
                                if (event.modifiers & Qt.ShiftModifier) {
                                    // Insert newline
                                    messageInputField.insert(messageInputField.cursorPosition, "\n");
                                    event.accepted = true;
                                } else {
                                    // Accept text
                                    const inputText = messageInputField.text;
                                    messageInputField.clear();
                                    root.handleInput(inputText);
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
                                // Try image paste first
                                const currentClipboardEntry = Cliphist.entries[0];
                                const cleanCliphistEntry = StringUtils.cleanCliphistEntry(currentClipboardEntry);
                                if (/^\d+\t\[\[.*binary data.*\d+x\d+.*\]\]$/.test(currentClipboardEntry)) {
                                    // First entry = currently copied entry = image?
                                    decodeImageAndAttachProc.handleEntry(currentClipboardEntry);
                                    event.accepted = true;
                                    return;
                                } else if (cleanCliphistEntry.startsWith("file://")) {
                                    // First entry = currently copied entry = image?
                                    const fileName = decodeURIComponent(cleanCliphistEntry);
                                    Ai.attachFile(fileName);
                                    event.accepted = true;
                                    return;
                                }
                                event.accepted = false; // No image, let text pasting proceed
                            } else if (event.key === Qt.Key_Escape) {
                                // Esc: cancel request > detach file > propagate (close sidebar)
                                if (Ai.requestActive) {
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
                            root.handleInput(inputText);
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

                property var commandsShown: [
                    {
                        name: "",
                        sendDirectly: false,
                        dontAddSpace: true
                    },
                    {
                        name: "clear",
                        sendDirectly: true
                    },
                ]

                ApiInputBoxIndicator {
                    // Model indicator
                    icon: "api"
                    text: Ai.getModel().name
                    tooltipText: Translation.tr("Current model: %1\nSet it with %2model MODEL").arg(Ai.getModel().name).arg(root?.commandPrefix ?? "")
                    onClickedAction: () => root.prefillCommand(root.commandPrefix + "model ")
                }

                ApiInputBoxIndicator {
                    // Tool indicator
                    icon: "service_toolbox"
                    text: Ai.currentTool.charAt(0).toUpperCase() + Ai.currentTool.slice(1)
                    tooltipText: Translation.tr("Current tool: %1\nSet it with %2tool TOOL").arg(Ai.currentTool).arg(root?.commandPrefix ?? "")
                    onClickedAction: () => root.prefillCommand(root.commandPrefix + "tool ")
                }

                ApiCommandButton {
                    // Attach button
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSurface
                        text: "attach_file"
                    }
                    onClicked: root.prefillCommand(root.commandPrefix + "attach ")
                    Accessible.name: Translation.tr("Attach a file")

                    StyledToolTip {
                        text: Translation.tr("Attach a file — paste an image or type a path")
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ButtonGroup {
                    // Command buttons
                    padding: 0

                    Repeater {
                        // Command buttons
                        model: commandButtonsRow.commandsShown
                        delegate: ApiCommandButton {
                            property string commandRepresentation: `${root.commandPrefix}${modelData.name}`
                            buttonText: commandRepresentation
                            downAction: () => {
                                if (modelData.sendDirectly) {
                                    root.handleInput(commandRepresentation);
                                } else {
                                    messageInputField.text = commandRepresentation + (modelData.dontAddSpace ? "" : " ");
                                    messageInputField.cursorPosition = messageInputField.text.length;
                                    messageInputField.forceActiveFocus();
                                }
                                if (modelData.name === "clear") {
                                    messageInputField.text = "";
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
