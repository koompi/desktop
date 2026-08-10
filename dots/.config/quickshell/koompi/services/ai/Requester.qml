pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * One turn of inference: builds the curl script, streams the reply back into the
 * conversation, and owns cancel, retry and the queue of sends waiting on it.
 * `engine` is the Ai facade.
 */
QtObject {
    id: root

    property QtObject engine

    readonly property bool running: proc.running

    // Dead-host cooldown (#10)
    property int _errorStreak: 0
    property bool _cooldownActive: false

    // Stop / retry / queued sends
    property bool _cancelled: false
    property bool _retryAfterCancel: false
    property var _pendingSends: []

    readonly property FileView scriptFile: FileView {}

    readonly property Timer cooldownTimer: Timer {
        interval: 20000
        repeat: false
        onTriggered: { root._cooldownActive = false; root._errorStreak = 0; }
    }

    function markDone() {
        proc.message.done = true;
        if (root.engine.postResponseHook) {
            root.engine.postResponseHook();
            root.engine.postResponseHook = null;
        }
        root.engine.saveChat("lastSession");
        root.engine.responseFinished();
        // Append assistant turn to episodic log (#7)
        if (MemoryService.ready) {
            const evContent = proc.message.rawContent;
            if (evContent && evContent.trim().length > 0 && !proc.message.functionCall) {
                MemoryService.appendEvent(root.engine.sessionId, "assistant", evContent, []);
            }
        }
        // The only decision classify_step could ever return was this token check (#8, D18)
        const conversation = root.engine.conversation;
        const lastMsg = conversation.messageByID[conversation.messageIDs[conversation.messageIDs.length - 1]];
        const total = root.engine.tokenCount.total;
        const nearThreshold = (lastMsg?.role === "assistant")
            && total > 0 && total > root.engine.compactionThreshold * 0.85;
        if (!root.engine.compacting && (nearThreshold || total > root.engine.compactionThreshold)) {
            root.engine.compact(null);
        }
    }

    // LiteRT-LM drops digits out of the reply when the whole tool array rides
    // along: "Core Ultra 7 258V" comes back "Core Ultra7 58V", "953.9 GiB" as
    // "95.9 GiB", at temperature 0, and one tool or none is clean. The turn that
    // reads a tool result back to the user is the one where numbers matter, and
    // it does not need to call anything, so it goes out bare.
    function toolsForTurn(model, messages) {
        const declared = root.engine.tools[model.api_format][root.engine.currentTool];
        if (!/(127\.0\.0\.1|localhost)/.test(model?.endpoint ?? "")) return declared;
        const last = messages[messages.length - 1];
        return (last?.functionName ?? "").length > 0 ? [] : declared;
    }

    function makeRequest() {
        const model = root.engine.models[root.engine.currentModelId];

        // Fetch API keys if needed
        if (model?.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();

        proc.currentStrategy = root.engine.currentApiStrategy;
        proc.currentStrategy.reset(); // Reset strategy state

        /* Put API key in environment variable */
        if (model.requires_key) proc.environment[`${root.engine.apiKeyEnvVarName}`] = root.engine.apiKeys ? (root.engine.apiKeys[model.key_id] ?? "") : ""

        /* Build endpoint, request data */
        const endpoint = root.engine.currentApiStrategy.buildEndpoint(model);
        const conversation = root.engine.conversation;
        const messageArray = conversation.messageIDs.map(id => conversation.messageByID[id]);
        const filteredMessageArray = messageArray.filter(message => message.role !== root.engine.interfaceRole);
        const data = root.engine.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.engine.systemPrompt, root.engine.temperature, root.toolsForTurn(model, filteredMessageArray), root.engine.pendingFilePath);

        let requestHeaders = {
            "Content-Type": "application/json",
        }

        /* Create local message object */
        proc.message = root.engine.aiMessageComponent.createObject(root, {
            "role": "assistant",
            "model": root.engine.currentModelId,
            "content": "",
            "rawContent": "",
            "thinking": true,
            "done": false,
            "timestamp": Date.now(),
        });
        conversation.appendMessage(proc.message);

        /* Build header string for curl */
        let headerString = Object.entries(requestHeaders)
            .filter(([k, v]) => v && v.length > 0)
            .map(([k, v]) => `-H '${k}: ${v}'`)
            .join(' ');

        /* Get authorization header from strategy */
        const authHeader = proc.currentStrategy.buildAuthorizationHeader(root.engine.apiKeyEnvVarName);

        /* Script shebang */
        const scriptShebang = "#!/usr/bin/env bash\n";

        /* Create extra setup when there's an attached file */
        let scriptFileSetupContent = ""
        if (root.engine.pendingFilePath && root.engine.pendingFilePath.length > 0) {
            proc.message.localFilePath = root.engine.pendingFilePath;
            scriptFileSetupContent = proc.currentStrategy.buildScriptFileSetup(root.engine.pendingFilePath);
            root.engine.pendingFilePath = ""
        }

        /* Create command string */
        let scriptRequestContent = ""
        scriptRequestContent += `curl --no-buffer "${endpoint}"`
            + ` ${headerString}`
            + (authHeader ? ` ${authHeader}` : "")
            + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
            + "\n"

        /* Send the request */
        const scriptContent = proc.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
        const shellScriptPath = CF.FileUtils.trimFileProtocol(root.engine.requestScriptFilePath)
        root.scriptFile.path = Qt.resolvedUrl(shellScriptPath)
        root.scriptFile.setText(scriptContent)
        proc.command = proc.baseCommand.concat([shellScriptPath]);
        proc.running = true
    }

    readonly property Process proc: Process {
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy
        property var pendingFunctionCall: null

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                root.engine.tokenStreamed()
                if (proc.message.thinking) proc.message.thinking = false;

                // Handle response line
                try {
                    const result = proc.currentStrategy.parseResponseLine(data, proc.message);

                    if (result.functionCall) {
                        proc.message.functionCall = result.functionCall;
                        // curl still alive here, so makeRequest() would be a no-op; dispatch on exit
                        proc.pendingFunctionCall = { call: result.functionCall, message: proc.message };
                    }
                    if (result.tokenUsage) {
                        root.engine.tokenCount.input = result.tokenUsage.input;
                        root.engine.tokenCount.output = result.tokenUsage.output;
                        root.engine.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        root.markDone();
                    }

                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    proc.message.rawContent += data;
                    proc.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = proc.currentStrategy.onRequestFinished(proc.message);

            if (result.finished) {
                root.markDone();
            } else if (!proc.message.done) {
                root.markDone();
            }

            const pendingCall = proc.pendingFunctionCall;
            proc.pendingFunctionCall = null;

            if (root._cancelled) {
                // User stopped the response - not an error
                root._cancelled = false;
                if (root._retryAfterCancel) {
                    root._retryAfterCancel = false;
                    // Drop the stalled assistant message and re-request with the same context
                    const conversation = root.engine.conversation;
                    const lastIdx = conversation.messageIDs.length - 1;
                    const lastMsg = conversation.messageByID[conversation.messageIDs[lastIdx]];
                    if (lastMsg && lastMsg.role === "assistant") conversation.removeMessage(lastIdx);
                    root.makeRequest();
                } else if (root._pendingSends.length > 0) {
                    const next = root._pendingSends[0];
                    root._pendingSends = root._pendingSends.slice(1);
                    Qt.callLater(() => root.sendUserMessage(next));
                }
                return;
            }

            // Handle error responses
            if (proc.message.content.includes("API key not valid")) {
                root.engine.addApiKeyAdvice(root.engine.models[proc.message.model]);
            }

            // Dead-host cooldown (#10): track consecutive failures
            const isError = exitCode !== 0 || proc.message.rawContent.trim().length === 0;
            if (isError) {
                root._errorStreak++;
                if (root._errorStreak >= 2) {
                    root._cooldownActive = true;
                    root.cooldownTimer.restart();
                }
            } else {
                root._errorStreak = 0;
            }

            if (pendingCall) {
                Qt.callLater(() => root.engine.toolRunner.handleFunctionCall(pendingCall.call.name, pendingCall.call.args, pendingCall.message));
                return;
            }

            // Send the next queued user message, if any
            if (!isError && root._pendingSends.length > 0) {
                const next = root._pendingSends[0];
                root._pendingSends = root._pendingSends.slice(1);
                Qt.callLater(() => root.sendUserMessage(next));
            }
        }
    }

    function cancelRequest() {
        if (!proc.running) return;
        root._cancelled = true;
        proc.running = false;
    }

    function retryRequest() {
        if (proc.running) {
            root._retryAfterCancel = true;
            root.cancelRequest();
        } else {
            root.makeRequest();
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        if (root.running) {
            root._pendingSends = [...root._pendingSends, message];
            root.engine.addMessage(Translation.tr("Queued — will send when the current response finishes."), root.engine.interfaceRole);
            return;
        }
        if (root._cooldownActive) {
            root.engine.addMessage(Translation.tr("API is unavailable. Retrying automatically in 20 seconds."), root.engine.interfaceRole);
            return;
        }
        if (root.engine.compacting) {
            root.engine.conversation._queuedMessage = message;
            root.engine.addMessage("Compacting context… your message will send when done.", root.engine.interfaceRole);
            return;
        }
        root.engine.addMessage(message, "user");
        root.engine.saveChat("lastSession");
        // The user's own words are the half worth learning from. Logging only the
        // assistant turn left consolidation promoting the model's output into memory
        // and dropping every correction the user made to it.
        if (MemoryService.ready) MemoryService.appendEvent(root.engine.sessionId, "user", message, []);

        // Auto-RAG: pull relevant long-term memories before asking the model.
        // MemoryService guarantees the callback fires (timeout -> null), so the
        // request is never blocked by the memory daemon.
        const memCfg = Config.options?.ai?.memory;
        if (memCfg?.enable && memCfg?.autoRecall && MemoryService.ready) {
            MemoryService.recall(message, memCfg.recallCount, results => {
                root.engine.recalledMemories = root.engine.formatMemories(results);
                root.makeRequest();
            });
        } else {
            root.engine.recalledMemories = "";
            root.makeRequest();
        }
    }
}
