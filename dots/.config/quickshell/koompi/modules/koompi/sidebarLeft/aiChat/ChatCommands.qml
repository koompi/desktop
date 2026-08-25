import qs
import qs.services
import qs.modules.common
import QtQuick
import Quickshell
import "testMessage.js" as TestMessage

// The slash-command table and its dispatcher. `run(name, args)` executes a command
// and reports whether one by that name exists; the caller decides what an unknown
// name means. Completion reads `allCommands` and `commandGroups`.
QtObject {
    id: root
    property string prefix: "/"

    readonly property var commandGroups: [
        { id: "chat", title: Translation.tr("This conversation") },
        { id: "memory", title: Translation.tr("What it remembers") },
        { id: "agent", title: Translation.tr("Doing things") },
        { id: "config", title: Translation.tr("Settings — now in Settings > AI") }
    ]

    function groupTitleOf(groupId) {
        return root.commandGroups.find(group => group.id === groupId)?.title ?? "";
    }

    property var movedNoticesShown: ({})
    function noteThatItMoved(commandName) {
        if (root.movedNoticesShown[commandName])
            return;
        root.movedNoticesShown[commandName] = true;
        Ai.addMessage(Translation.tr("`%1%2` lives in **Settings > AI** now. It keeps working here for this release.").arg(root.prefix).arg(commandName), Ai.interfaceRole);
    }

    property var allCommands: [
        {
            name: "attach",
            group: "chat",
            argType: "path",
            usage: Translation.tr("%1attach PATH").arg(root.prefix),
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
            usage: Translation.tr("%1save CHAT_NAME").arg(root.prefix),
            description: Translation.tr("Save chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1save CHAT_NAME").arg(root.prefix), Ai.interfaceRole);
                    return;
                }
                Ai.saveChat(joinedArgs);
            }
        },
        {
            name: "load",
            group: "chat",
            argType: "chat",
            usage: Translation.tr("%1load CHAT_NAME").arg(root.prefix),
            description: Translation.tr("Load chat"),
            execute: args => {
                const joinedArgs = args.join(" ");
                if (joinedArgs.trim().length == 0) {
                    Ai.addMessage(Translation.tr("Usage: %1load CHAT_NAME").arg(root.prefix), Ai.interfaceRole);
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
            description: Translation.tr("Snapshot this session to memory. Resume later with %1resume SESSION_ID.").arg(root.prefix),
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
            usage: Translation.tr("%1resume SESSION_ID").arg(root.prefix),
            description: Translation.tr("Restore a forked session."),
            execute: args => {
                const forkId = (args[0] ?? "").trim();
                if (!forkId) {
                    Ai.addMessage(Translation.tr("Usage: %1resume SESSION_ID").arg(root.prefix), Ai.interfaceRole);
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
                    return "**" + group.title + "**\n" + inGroup.map(command => `- \`${command.usage ?? (root.prefix + command.name)}\` — ${command.description}`).join("\n");
                }).filter(section => section.length > 0);
                Ai.addMessage(lines.join("\n\n") + "\n\n" + Translation.tr("Press F1 for the keys."), Ai.interfaceRole);
            }
        },
        {
            name: "remember",
            group: "memory",
            argType: "text",
            usage: Translation.tr("%1remember SOMETHING").arg(root.prefix),
            description: Translation.tr("Store a fact in long-term memory by hand."),
            execute: args => {
                const text = args.join(" ").trim();
                if (text.length === 0) {
                    Ai.addMessage(Translation.tr("Usage: %1remember SOMETHING TO REMEMBER").arg(root.prefix), Ai.interfaceRole);
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
                    Ai.addMessage(Translation.tr("**Stored memories** (forget with %1forget ID):\n%2").arg(root.prefix).arg(lines), Ai.interfaceRole);
                });
            }
        },
        {
            name: "forget",
            group: "memory",
            argType: "memory",
            usage: Translation.tr("%1forget MEMORY_ID").arg(root.prefix),
            description: Translation.tr("Forget a memory by id."),
            execute: args => {
                const id = parseInt(args[0]);
                if (isNaN(id)) {
                    Ai.addMessage(Translation.tr("Usage: %1forget MEMORY_ID").arg(root.prefix), Ai.interfaceRole);
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
            usage: Translation.tr("%1owner YOUR_NAME").arg(root.prefix),
            description: Translation.tr("Set the name the assistant should call you by."),
            execute: args => {
                const name = args.join(" ").trim();
                if (name.length === 0 || name === "get") {
                    const current = Persistent.states.ai.ownerName;
                    if (current.length > 0) {
                        Ai.addMessage(Translation.tr("You're registered as **%1**. Change it with %2owner NEW_NAME").arg(current).arg(root.prefix), Ai.interfaceRole);
                    } else {
                        Ai.addMessage(Translation.tr("No owner name set yet. Register with %1owner YOUR_NAME").arg(root.prefix), Ai.interfaceRole);
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
                const ownerLine = current.length > 0 ? current : Translation.tr("unknown (tell me your name or use %1owner)").arg(root.prefix);
                Ai.addMessage(Translation.tr("**Assistant**: %1\n**Owner**: %2\n**Login user**: %3").arg(Ai.aiName).arg(ownerLine).arg(SystemInfo.username), Ai.interfaceRole);
            }
        },
        {
            name: "tool",
            group: "agent",
            argType: "tool",
            usage: Translation.tr("%1tool TOOL_NAME").arg(root.prefix),
            description: Translation.tr("Choose what the model is allowed to reach for."),
            execute: args => {
                if (args.length == 0 || args[0] == "get") {
                    Ai.addMessage(Translation.tr("Usage: %1tool TOOL_NAME").arg(root.prefix), Ai.interfaceRole);
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
            usage: Translation.tr("%1research QUERY").arg(root.prefix),
            description: Translation.tr("Think, search, synthesise — up to five rounds."),
            execute: args => {
                const query = args.join(" ").trim();
                if (!query) {
                    Ai.addMessage(Translation.tr("Usage: %1research QUERY").arg(root.prefix), Ai.interfaceRole);
                    return;
                }
                ResearchService.start(query);
            }
        },
        {
            name: "task",
            group: "agent",
            argType: "text",
            usage: Translation.tr("%1task DESCRIPTION").arg(root.prefix),
            description: Translation.tr("Run a subtask in a fresh context; the result comes back here."),
            execute: args => {
                const desc = args.join(" ").trim();
                if (!desc) {
                    Ai.addMessage(Translation.tr("Usage: %1task DESCRIPTION").arg(root.prefix), Ai.interfaceRole);
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
            usage: Translation.tr("%1model MODEL").arg(root.prefix),
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
            usage: Translation.tr("%1prompt FILE").arg(root.prefix),
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
            usage: Translation.tr("%1key API_KEY").arg(root.prefix),
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
            usage: Translation.tr("%1endpoint [remote|local] URL").arg(root.prefix),
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
            usage: Translation.tr("%1temp VALUE").arg(root.prefix),
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
            name: "test", group: "chat", argType: "", description: Translation.tr("Markdown test"),
            execute: () => Ai.addMessage(TestMessage.text(Quickshell.shellPath("assets/icons/arch-symbolic.svg"), Appearance.font.pixelSize.small), Ai.interfaceRole)
        }] : []),
    ]

    // True when a command called `name` exists (and has now run).
    function run(name, args) {
        const commandObj = root.allCommands.find(cmd => cmd.name === `${name}`);
        if (!commandObj)
            return false;
        commandObj.execute(args);
        return true;
    }
}
