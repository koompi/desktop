pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * One turn of inference: builds the curl script, streams the reply back into the
 * conversation, and owns cancel, retry, the deadline and the queue of sends waiting
 * on it. `engine` is the Ai facade.
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
    property bool _timedOut: false
    property var _pendingSends: []

    // A turn has an end. LiteRT-LM serves one request at a time, so a hung turn holds
    // every inference on the machine until something kills it.
    property int deadlineSec: Math.max(10, Config.options?.ai?.requestTimeoutSec ?? 180)
    property double _sentAt: 0

    // Recall must not own the first token. Whatever the daemon has by the time this
    // budget runs out is what the turn goes out with.
    property int recallBudgetMs: Math.max(1, Config.options?.ai?.memory?.recallBudgetMs ?? 800)
    property var _recallGate: null

    // The request body is the whole conversation. It goes in the user's own runtime
    // directory (0700) and is chmodded 0600 before curl reads it, never in shared /tmp.
    readonly property string scriptDirPath: {
        const runtime = Quickshell.env("XDG_RUNTIME_DIR") ?? "";
        return runtime.length > 0 ? `${runtime}/quickshell/ai` : `${Quickshell.env("HOME")}/.cache/quickshell/ai`;
    }
    readonly property string scriptFilePath: `${root.scriptDirPath}/request.sh`

    readonly property FileView scriptFile: FileView {}

    readonly property Timer cooldownTimer: Timer {
        interval: 20000
        repeat: false
        onTriggered: { root._cooldownActive = false; root._errorStreak = 0; }
    }

    readonly property Timer deadlineTimer: Timer {
        repeat: false
        onTriggered: root.expireRequest()
    }

    readonly property Timer recallTimer: Timer {
        repeat: false
        onTriggered: { if (root._recallGate) root._recallGate(); }
    }

    function expireRequest() {
        if (!proc.running) return;
        root._timedOut = true;
        console.log(`[AI] request exceeded its ${root.deadlineSec}s deadline, killing curl`);
        proc.running = false;
    }

    function markDone() {
        if (proc.message.done) return; // onExited and the stream both reach here
        proc.message.done = true;
        root.deadlineTimer.stop();
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

    // Measured, not guessed: gemma4-e4b on LiteRT-LM relays numbers correctly with up
    // to 1461 bytes of compact tool JSON and starts dropping digits at 1965, at
    // temperature 0. The turn that reads a tool result back to the user is the one
    // where numbers matter and the one that does not need to call anything, so when
    // the declarations are over the model's measured ceiling it goes out bare.
    function toolsForTurn(model, messages) {
        const declared = root.engine.tools[model.api_format][root.engine.currentTool];
        const limit = model?.toolBlockByteLimit ?? 0;
        if (limit <= 0) return declared;
        const last = messages[messages.length - 1];
        const answeringATool = (last?.toolCallId ?? "").length > 0 || (last?.functionName ?? "").length > 0;
        if (!answeringATool) return declared;
        return JSON.stringify(declared).length > limit ? [] : declared;
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
            // what the tools of this turn returned; other producers append to it
            "sources": root.engine.toolRunner.takeTurnSources(),
        });
        conversation.appendMessage(proc.message);

        /* Build header string for curl */
        let headerString = Object.entries(requestHeaders)
            .filter(([k, v]) => v && v.length > 0)
            .map(([k, v]) => `-H '${k}: ${v}'`)
            .join(' ');

        /* Get authorization header from strategy */
        const authHeader = proc.currentStrategy.buildAuthorizationHeader(root.engine.apiKeyEnvVarName, model);

        /* Script shebang */
        const scriptShebang = "#!/usr/bin/env bash\n";

        /* Create extra setup when there's an attached file */
        let scriptFileSetupContent = ""
        if (root.engine.pendingFilePath && root.engine.pendingFilePath.length > 0) {
            proc.message.localFilePath = root.engine.pendingFilePath;
            scriptFileSetupContent = proc.currentStrategy.buildScriptFileSetup(root.engine.pendingFilePath);
            root.engine.pendingFilePath = ""
        }

        /* Create command string. `exec` so the kill lands on curl itself rather than on
           a bash that leaves it holding the server's only inference slot, and
           --max-time so curl gives up even if this shell is not around to kill it. */
        let scriptRequestContent = ""
        scriptRequestContent += `exec curl --no-buffer --max-time ${root.deadlineSec} "${endpoint}"`
            + ` ${headerString}`
            + (authHeader ? ` ${authHeader}` : "")
            + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
            + "\n"

        /* Send the request */
        const scriptContent = proc.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
        const shellScriptPath = CF.FileUtils.trimFileProtocol(root.scriptFilePath)
        root.scriptFile.path = Qt.resolvedUrl(shellScriptPath)
        root.scriptFile.setText(scriptContent)
        proc.command = proc.baseCommand.concat([shellScriptPath]);
        root._timedOut = false;
        root._sentAt = Date.now();
        root.deadlineTimer.interval = root.deadlineSec * 1000;
        root.deadlineTimer.restart();
        proc.running = true
    }

    readonly property Process proc: Process {
        // the body is the whole conversation, so it is readable by this user only
        property list<string> baseCommand: ["bash", "-c", 'chmod 600 "$1" 2>/dev/null; exec bash "$1"', "--"]
        property AiMessageData message
        property ApiStrategy currentStrategy
        property var pendingFunctionCalls: null

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                root.engine.tokenStreamed()
                if (proc.message.thinking) proc.message.thinking = false;

                // Handle response line
                try {
                    const result = proc.currentStrategy.parseResponseLine(data, proc.message);

                    if (result.functionCall || result.functionCalls) {
                        proc.message.functionCall = result.functionCall;
                        // curl still alive here, so makeRequest() would be a no-op; dispatch on exit
                        proc.pendingFunctionCalls = {
                            calls: result.functionCalls ?? [result.functionCall],
                            message: proc.message
                        };
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
            root.deadlineTimer.stop();
            proc.currentStrategy.onRequestFinished(proc.message); // flushes any trailing buffer
            root.markDone(); // idempotent; both this and the stream reach it

            const pending = proc.pendingFunctionCalls;
            proc.pendingFunctionCalls = null;

            if (root._timedOut) {
                root._timedOut = false;
                const waited = Math.round((Date.now() - root._sentAt) / 1000);
                console.log(`[AI] curl exited ${exitCode} after the deadline, slot released`);
                root.engine.addMessage(
                    Translation.tr("No reply after %1s, so the request was stopped and the model's slot freed. Try again, or ask something shorter.").arg(waited),
                    root.engine.interfaceRole);
                return;
            }

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

            if (pending) {
                Qt.callLater(() => root.engine.toolRunner.runCalls(pending.calls, pending.message));
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
        root.deadlineTimer.stop();
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

        // Auto-RAG: pull relevant long-term memories before asking the model, but on a
        // budget. Whichever comes first — the daemon or the clock — sends the request,
        // and a late answer is applied to the next turn rather than delaying this one.
        const memCfg = Config.options?.ai?.memory;
        if (memCfg?.enable && memCfg?.autoRecall && MemoryService.ready) {
            root.engine.recalledMemories = "";
            const fire = () => {
                if (!root._recallGate) return;
                root._recallGate = null;
                root.recallTimer.stop();
                root.makeRequest();
            };
            root._recallGate = fire;
            root.recallTimer.interval = root.recallBudgetMs;
            root.recallTimer.restart();
            MemoryService.recall(message, memCfg.recallCount, results => {
                root.engine.recalledMemories = root.engine.formatMemories(results);
                fire();
            });
        } else {
            root.engine.recalledMemories = "";
            root.makeRequest();
        }
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", "-m", "700", root.scriptDirPath])
}
