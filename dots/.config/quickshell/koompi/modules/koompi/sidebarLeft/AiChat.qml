import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.modules.koompi.sidebarLeft.aiChat
import qs.modules.koompi.sidebarLeft.aiChat.activity
import qs.modules.koompi.sidebarLeft.aiChat.composer
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
        // Tab and Backtab move focus. Grabbing them here is what kept the
        // transcript unreachable from the keyboard.
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab)
            return;
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

    readonly property var commandGroups: [
        {
            id: "chat",
            title: Translation.tr("This conversation")
        },
        {
            id: "memory",
            title: Translation.tr("What it remembers")
        },
        {
            id: "agent",
            title: Translation.tr("Doing things")
        },
        {
            id: "config",
            title: Translation.tr("Settings — now in Settings > AI")
        }
    ]

    function groupTitleOf(groupId) {
        return root.commandGroups.find(group => group.id === groupId)?.title ?? "";
    }

    property var movedNoticesShown: ({})
    function noteThatItMoved(commandName) {
        if (root.movedNoticesShown[commandName])
            return;
        root.movedNoticesShown[commandName] = true;
        Ai.addMessage(Translation.tr("`%1%2` lives in **Settings > AI** now. It keeps working here for this release.").arg(root.commandPrefix).arg(commandName), Ai.interfaceRole);
    }

    property var allCommands: [
        {
            name: "attach",
            group: "chat",
            argType: "path",
            usage: Translation.tr("%1attach PATH").arg(root.commandPrefix),
            description: Translation.tr("Send a file with the next message. Only a model that reads files will use it."),
            execute: args => {
                Ai.attachFile(args.join(" ").trim());
            }
        },
        {
            name: "clear",
            group: "chat",
            argType: "",
            description: Translation.tr("Clear chat history"),
            execute: () => {
                Ai.clearMessages();
            }
        },
        {
            name: "save",
            group: "chat",
            argType: "chat",
            usage: Translation.tr("%1save CHAT_NAME").arg(root.commandPrefix),
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
            group: "chat",
            argType: "chat",
            usage: Translation.tr("%1load CHAT_NAME").arg(root.commandPrefix),
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
            name: "compact",
            group: "chat",
            argType: "",
            description: Translation.tr("Summarise the older turns so the model keeps its quality."),
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
            group: "chat",
            argType: "",
            description: Translation.tr("Snapshot this session to memory. Resume later with %1resume SESSION_ID.").arg(root.commandPrefix),
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
            group: "chat",
            argType: "text",
            usage: Translation.tr("%1resume SESSION_ID").arg(root.commandPrefix),
            description: Translation.tr("Restore a forked session."),
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
            name: "help",
            group: "chat",
            argType: "",
            description: Translation.tr("List every command, and every key this chat listens for."),
            execute: () => {
                const lines = root.commandGroups.map(group => {
                    const inGroup = root.allCommands.filter(command => command.group === group.id);
                    if (inGroup.length === 0)
                        return "";
                    return "**" + group.title + "**\n" + inGroup.map(command => `- \`${command.usage ?? (root.commandPrefix + command.name)}\` — ${command.description}`).join("\n");
                }).filter(section => section.length > 0);
                Ai.addMessage(lines.join("\n\n") + "\n\n" + Translation.tr("Press F1 for the keys."), Ai.interfaceRole);
            }
        },
        {
            name: "remember",
            group: "memory",
            argType: "text",
            usage: Translation.tr("%1remember SOMETHING").arg(root.commandPrefix),
            description: Translation.tr("Store a fact in long-term memory by hand."),
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
            group: "memory",
            argType: "",
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
            group: "memory",
            argType: "memory",
            usage: Translation.tr("%1forget MEMORY_ID").arg(root.commandPrefix),
            description: Translation.tr("Forget a memory by id."),
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
            name: "owner",
            group: "memory",
            argType: "text",
            usage: Translation.tr("%1owner YOUR_NAME").arg(root.commandPrefix),
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
            group: "memory",
            argType: "",
            description: Translation.tr("Show who the assistant thinks you are."),
            execute: () => {
                const current = Persistent.states.ai.ownerName;
                const ownerLine = current.length > 0 ? current : Translation.tr("unknown (tell me your name or use %1owner)").arg(root.commandPrefix);
                Ai.addMessage(Translation.tr("**Assistant**: %1\n**Owner**: %2\n**Login user**: %3").arg(Ai.aiName).arg(ownerLine).arg(SystemInfo.username), Ai.interfaceRole);
            }
        },
        {
            name: "tool",
            group: "agent",
            argType: "tool",
            usage: Translation.tr("%1tool TOOL_NAME").arg(root.commandPrefix),
            description: Translation.tr("Choose what the model is allowed to reach for."),
            execute: args => {
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
            name: "research",
            group: "agent",
            argType: "text",
            usage: Translation.tr("%1research QUERY").arg(root.commandPrefix),
            description: Translation.tr("Think, search, synthesise — up to five rounds."),
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
            group: "agent",
            argType: "text",
            usage: Translation.tr("%1task DESCRIPTION").arg(root.commandPrefix),
            description: Translation.tr("Run a subtask in a fresh context; the result comes back here."),
            execute: args => {
                const desc = args.join(" ").trim();
                if (!desc) {
                    Ai.addMessage(Translation.tr("Usage: %1task DESCRIPTION").arg(root.commandPrefix), Ai.interfaceRole);
                    return;
                }
                Ai.spawnSubtask(desc);
            }
        },
        {
            name: "model",
            group: "config",
            argType: "model",
            moved: true,
            usage: Translation.tr("%1model MODEL").arg(root.commandPrefix),
            description: Translation.tr("Choose which model answers."),
            execute: args => {
                root.noteThatItMoved("model");
                Ai.setModel(args[0]);
            }
        },
        {
            name: "prompt",
            group: "config",
            argType: "prompt",
            moved: true,
            usage: Translation.tr("%1prompt FILE").arg(root.commandPrefix),
            description: Translation.tr("Replace the system prompt with a file."),
            execute: args => {
                if (args.length === 0 || args[0] === "get") {
                    Ai.printPrompt();
                    return;
                }
                root.noteThatItMoved("prompt");
                Ai.loadPrompt(args.join(" ").trim());
            }
        },
        {
            name: "key",
            group: "config",
            argType: "text",
            moved: true,
            usage: Translation.tr("%1key API_KEY").arg(root.commandPrefix),
            description: Translation.tr("Set the API key a remote model needs."),
            execute: args => {
                if (args[0] == "get") {
                    Ai.printApiKey();
                } else {
                    root.noteThatItMoved("key");
                    Ai.setApiKey(args[0]);
                }
            }
        },
        {
            name: "endpoint",
            group: "config",
            argType: "text",
            moved: true,
            usage: Translation.tr("%1endpoint [remote|local] URL").arg(root.commandPrefix),
            description: Translation.tr("Point a model slot at a different server."),
            execute: args => {
                root.noteThatItMoved("endpoint");
                Ai.setEndpoint(args.join(" ").trim());
            }
        },
        {
            name: "temp",
            group: "config",
            argType: "text",
            moved: true,
            usage: Translation.tr("%1temp VALUE").arg(root.commandPrefix),
            description: Translation.tr("How much the model wanders. 0 to 2 for Gemini, 0 to 1 elsewhere."),
            execute: args => {
                if (args.length == 0 || args[0] == "get") {
                    Ai.printTemperature();
                } else {
                    root.noteThatItMoved("temp");
                    const temp = parseFloat(args[0]);
                    Ai.setTemperature(temp);
                }
            }
        },
        ...(Config.options?.ai?.debugCommands ?? false ? [{
            name: "test",
            group: "chat",
            argType: "",
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
    property bool helpShown: false
    property bool attachMenuShown: false

    property var inputHistory: []
    property int historyCursor: -1
    property string historyDraft: ""

    function prefillCommand(cmd) {
        messageInputField.text = cmd;
        messageInputField.cursorPosition = messageInputField.text.length;
        messageInputField.forceActiveFocus();
    }

    function insertIntoComposer(text) {
        messageInputField.insert(messageInputField.cursorPosition, text);
        messageInputField.forceActiveFocus();
    }

    function openAiSettings() {
        const page = SettingsPages.list.find(entry => entry.component.endsWith("AiConfig.qml"));
        if (page)
            SettingsPages.open(page);
    }

    function focusTranscript() {
        if (messageListView.count === 0)
            return false;
        messageListView.currentIndex = messageListView.count - 1;
        messageListView.positionViewAtEnd();
        messageListView.forceActiveFocus(Qt.TabFocusReason);
        return true;
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
        root.historyCursor = -1;
        root.historyDraft = "";
        if (inputText.trim().length > 0 && root.inputHistory[root.inputHistory.length - 1] !== inputText) {
            root.inputHistory = root.inputHistory.concat([inputText]).slice(-50);
        }
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

    // One completion source. A command declares the type of its argument and the
    // list comes from that type; adding a command with arguments adds a case, not
    // another copy of the filter.
    function argumentCandidates(argType) {
        if (argType === "model") {
            return Ai.modelList.map(modelId => ({
                value: modelId,
                label: Ai.models[modelId]?.name ?? modelId,
                description: Ai.models[modelId]?.description ?? "",
                groupTitle: Translation.tr("Models")
            }));
        }
        if (argType === "prompt") {
            return Ai.promptFiles.map(file => ({
                value: file,
                label: FileUtils.trimFileExt(FileUtils.fileNameForPath(file)),
                description: Translation.tr("Load prompt from %1").arg(file),
                groupTitle: Translation.tr("Prompt files")
            }));
        }
        if (argType === "chat") {
            return Ai.savedChats.map(file => {
                const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file)).trim();
                return {
                    value: chatName,
                    label: chatName,
                    description: Translation.tr("Saved chat %1").arg(chatName),
                    groupTitle: Translation.tr("Saved chats")
                };
            });
        }
        if (argType === "tool") {
            return Ai.availableTools.map(tool => ({
                value: tool,
                label: tool,
                description: Ai.toolDescriptions[tool] ?? "",
                groupTitle: Translation.tr("Tools")
            }));
        }
        return [];
    }

    readonly property var commandEntries: root.allCommands.map(command => ({
        value: `${root.commandPrefix}${command.name}`,
        label: `${root.commandPrefix}${command.name}`,
        description: command.description,
        group: command.group,
        groupTitle: root.groupTitleOf(command.group),
        badge: command.argType.length > 0 ? command.argType : ""
    }))

    function narrow(candidates, query) {
        if (query.length === 0)
            return candidates;
        const results = Fuzzy.go(query, candidates.map(candidate => ({
            name: Fuzzy.prepare(candidate.value),
            candidate: candidate
        })), {
            all: true,
            key: "name"
        });
        return results.map(result => result.obj.candidate);
    }

    // Fuzzy ranking scrambles the order, and a palette whose headings repeat is
    // not grouped. Bucket rather than sort: the engine's sort is not stable, and
    // it reversed each group's ranking.
    function byGroup(entries) {
        const out = [];
        root.commandGroups.forEach(group => {
            entries.forEach(entry => {
                if ((entry.group ?? "") === group.id)
                    out.push(entry);
            });
        });
        entries.forEach(entry => {
            if (out.indexOf(entry) === -1)
                out.push(entry);
        });
        return out;
    }

    function updateSuggestions() {
        const text = messageInputField.text;
        if (text.length === 0 || !text.startsWith(root.commandPrefix)) {
            root.suggestionQuery = "";
            root.suggestionList = [];
            return;
        }
        const firstSpace = text.indexOf(" ");
        const command = root.allCommands.find(entry => entry.name === (firstSpace === -1 ? text.substring(1) : text.substring(1, firstSpace)));
        if (firstSpace === -1 || !command || command.argType.length === 0 || root.argumentCandidates(command.argType).length === 0) {
            root.suggestionQuery = text;
            root.suggestionList = root.byGroup(root.narrow(root.commandEntries, text.substring(1)));
            return;
        }
        root.suggestionQuery = text.split(" ")[1] ?? "";
        // The first word is the command itself, so a suggestion taken before any
        // argument is typed has to carry the command with it.
        const prefix = text.trim().split(/\s+/).length === 1 ? `${root.commandPrefix}${command.name} ` : "";
        root.suggestionList = root.narrow(root.argumentCandidates(command.argType), root.suggestionQuery).map(candidate => ({
            value: `${prefix}${candidate.value}`,
            label: candidate.label,
            description: candidate.description,
            groupTitle: candidate.groupTitle
        }));
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

    ColumnLayout {
        id: columnLayout
        anchors {
            fill: parent
            margins: root.padding
        }
        spacing: root.padding

        Item {
            // Messages
            id: messageArea
            Layout.fillWidth: true
            Layout.fillHeight: true
            layer.enabled: true
            layer.effect: OpacityMask {
                maskSource: Rectangle {
                    width: messageArea.width
                    height: messageArea.height
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
                implicitWidth: Math.min(parent.width - 8, statusBar.implicitWidth + 10 * 2)
                implicitHeight: Math.max(statusBar.implicitHeight + 6 * 2, 38)
                radius: Appearance.rounding.normal - root.padding
                color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base
                Behavior on color {
                    animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
                }
                Behavior on implicitHeight {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }

                ChatStatusBar {
                    id: statusBar
                    anchors.centerIn: parent
                    width: parent.width - 10 * 2
                    stalled: root.stallDetected
                    active: root.visible
                    onStopRequested: {
                        Ai.cancelRequest();
                        root.stallDetected = false;
                    }
                    onRetryRequested: {
                        Ai.retryRequest();
                        root.stallDetected = false;
                    }
                    onSettingsRequested: root.openAiSettings()
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
                activeFocusOnTab: true

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

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backtab) {
                        messageInputField.forceActiveFocus();
                        event.accepted = true;
                    }
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
                icon: "auto_awesome"
                title: Translation.tr("Ask about this computer")
                description: Translation.tr("I read and change your settings,\nrun a command when you say yes,\nlook things up, and send an agent\nto inspect this machine.\n\nIt runs here. No key, no network.")
                descriptionHorizontalAlignment: Text.AlignHCenter
                shape: MaterialShape.Shape.PixelCircle
            }

            ColumnLayout { // Empty-state starters
                z: 2
                visible: Ai.messageIDs.length === 0 && messageInputField.text.length === 0
                anchors {
                    left: parent.left
                    right: parent.right
                    bottom: parent.bottom
                    leftMargin: 20
                    rightMargin: 20
                    bottomMargin: 20
                }
                spacing: 5

                Repeater {
                    // Every starter has to finish on the local model with no key and
                    // no network, so none of them may reach for ask_agent.
                    model: [
                        Translation.tr("What can you do on this computer?"),
                        Translation.tr("Run df -h and tell me how full my disk is"),
                        Translation.tr("Is my bar at the top or the bottom?")
                    ]
                    delegate: ApiCommandButton {
                        id: starterButton
                        required property string modelData
                        Layout.fillWidth: true
                        buttonText: starterButton.modelData
                        Accessible.name: starterButton.modelData
                        onClicked: {
                            messageInputField.clear();
                            root.handleInput(starterButton.modelData);
                        }
                    }
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
            radius: Appearance.rounding.full
            color: Appearance.colors.colLayer1
            Rectangle {
                readonly property real fill: Ai.tokenCount.total / Math.max(1, Ai.contextWindow)
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
                    text: Translation.tr("Context: %1 / %2 tokens\nInput: %3 — Output: %4").arg(Ai.tokenCount.total).arg(Ai.contextWindow).arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
                }
            }
        }
        StyledText {
            visible: Ai.tokenCount.total > 0
                && Ai.tokenCount.total >= Ai.contextWindow * 0.90
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

        CommandPalette { // Suggestions
            id: suggestions
            visible: root.suggestionList.length > 0 && messageInputField.text.length > 0
            Layout.fillWidth: true
            entries: root.suggestionList
            onAccepted: value => suggestions.acceptSuggestion(value)

            onEntriesChanged: suggestions.selectedIndex = 0

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
                if (suggestions.selectedIndex >= 0 && suggestions.selectedIndex < root.suggestionList.length) {
                    suggestions.acceptSuggestion(root.suggestionList[suggestions.selectedIndex].value);
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

        KeyboardHelpSheet {
            Layout.fillWidth: true
            shown: root.helpShown
            onDismissed: root.helpShown = false
        }

        AttachMenu {
            id: attachMenu
            Layout.fillWidth: true
            visible: root.attachMenuShown
            onVisibleChanged: if (visible) Qt.callLater(attachMenu.focusFirst)
            onInsertText: text => {
                root.insertIntoComposer(text);
                root.attachMenuShown = false;
            }
            onAttachPath: path => {
                Ai.attachFile(path);
                root.attachMenuShown = false;
            }
            onFilePathRequested: {
                root.prefillCommand(root.commandPrefix + "attach ");
                root.attachMenuShown = false;
            }
        }

        AgentActivityPanel { // the agent while it works, above the composer
            Layout.fillWidth: true
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
                        placeholderText: Ai.toolStatusLabel.length > 0
                            ? Ai.toolStatusLabel
                            : Translation.tr('Message the model... "%1" for commands').arg(root.commandPrefix)

                        background: null

                        onTextChanged: {
                            root.updateSuggestions();
                            if (messageInputField.text.length === 0) {
                                root.recallDismissed = false;
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
                            } else if (event.key === Qt.Key_Tab) {
                                // A TextArea consumes Tab, so the focus chain has to be
                                // walked by hand or the composer is a keyboard trap.
                                if (!root.focusTranscript())
                                    messageInputField.nextItemInFocusChain(true).forceActiveFocus(Qt.TabFocusReason);
                                event.accepted = true;
                            } else if (event.key === Qt.Key_F1) {
                                root.helpShown = !root.helpShown;
                                event.accepted = true;
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_K) {
                                root.prefillCommand(root.commandPrefix);
                                event.accepted = true;
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R) {
                                Ai.retryRequest();
                                root.stallDetected = false;
                                event.accepted = true;
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_End && messageInputField.text.length === 0) {
                                // Only with nothing typed: in a text field Ctrl+End is
                                // the caret's, and taking it would be a papercut.
                                messageListView.positionViewAtEnd();
                                event.accepted = true;
                            } else if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_Home && messageInputField.text.length === 0) {
                                messageListView.positionViewAtBeginning();
                                event.accepted = true;
                            } else if ((event.key === Qt.Key_PageUp || event.key === Qt.Key_PageDown) && event.modifiers === Qt.NoModifier) {
                                if (event.key === Qt.Key_PageUp) {
                                    messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
                                } else {
                                    messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
                                }
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
                                // Esc: close a sheet > cancel request > detach file > propagate (close sidebar)
                                if (root.helpShown || root.attachMenuShown) {
                                    root.helpShown = false;
                                    root.attachMenuShown = false;
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

                ApiInputBoxIndicator {
                    // Model indicator
                    icon: "api"
                    text: Ai.getModel().name
                    tooltipText: Translation.tr("Answering: %1\nChange it in Settings > AI").arg(Ai.getModel().name)
                    onClickedAction: () => root.openAiSettings()
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
                    colBackground: root.attachMenuShown ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSurface
                        text: "attach_file"
                    }
                    onClicked: root.attachMenuShown = !root.attachMenuShown
                    Accessible.name: Translation.tr("Attach")

                    StyledToolTip {
                        text: Translation.tr("A screenshot, the selection, this window, or a file")
                    }
                }

                ApiCommandButton {
                    // Keyboard help
                    colBackground: root.helpShown ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSurface
                        text: "keyboard"
                    }
                    onClicked: root.helpShown = !root.helpShown
                    Accessible.name: Translation.tr("Keyboard shortcuts")

                    StyledToolTip {
                        text: Translation.tr("Keys — F1")
                    }
                }

                ApiCommandButton {
                    // Hand the conversation to the full window
                    contentItem: MaterialSymbol {
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3onSurface
                        text: "open_in_full"
                    }
                    onClicked: GlobalStates.intelligenceOpen = true
                    Accessible.name: Translation.tr("Open the full window")

                    StyledToolTip {
                        text: Translation.tr("Threads, memory and activity, in a window")
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                ButtonGroup {
                    // Command buttons
                    padding: 0

                    ApiCommandButton {
                        buttonText: root.commandPrefix
                        Accessible.name: Translation.tr("Commands")
                        StyledToolTip {
                            text: Translation.tr("Commands — Ctrl+K")
                        }
                        downAction: () => root.prefillCommand(root.commandPrefix)
                    }
                    ApiCommandButton {
                        buttonText: `${root.commandPrefix}clear`
                        downAction: () => {
                            messageInputField.text = "";
                            root.handleInput(`${root.commandPrefix}clear`);
                        }
                    }
                }
            }
        }
    }
}
