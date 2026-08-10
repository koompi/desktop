pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * The chat itself: the message store, its persistence, and the compaction that
 * keeps it inside the model's context. `engine` is the Ai facade.
 */
QtObject {
    id: root

    property QtObject engine

    property var messageIDs: []
    property var messageByID: ({})

    property var _clearSnapshot: null
    readonly property bool canUndoClear: _clearSnapshot !== null

    // Subtask context isolation slot (#15)
    property var _savedContext: null

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    // Two orderings, and the difference is load-bearing. Appending the id re-runs
    // the chat list's visibility filter, and an id whose object is not in the map
    // yet reads as visible, so anything hidden has to be mapped first.
    function appendMessage(message) {
        const id = root.idForMessage(message);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = message;
        return id;
    }

    function attachMessage(message) {
        const id = root.idForMessage(message);
        root.messageByID[id] = message;
        root.messageIDs = [...root.messageIDs, id];
        return id;
    }

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = root.engine.aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
            "timestamp": Date.now(),
        });
        root.appendMessage(aiMessage);
    }

    function removeMessage(index) {
        if (index < 0 || index >= root.messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return root.engine.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "rawContent": `[[ Output of ${name} ]]${includeOutputInChat ? ("\n\n<think>\n" + output + "\n</think>") : ""}`,
            "functionName": name,
            "functionResponse": output,
            "thinking": false,
            "done": true,
            "timestamp": Date.now(),
            // "visibleToUser": false,
        });
    }

    // Hidden by default: tool plumbing is for the model, the user wants the answer.
    // The command-approval flow builds its own visible message instead.
    function addFunctionOutputMessage(name, output, visible = false) {
        const aiMessage = root.createFunctionOutputMessage(name, output);
        aiMessage.visibleToUser = visible;
        root.attachMessage(aiMessage);
    }

    function clearMessages(snapshot = true) {
        if (snapshot && root.messageIDs.length > 0) {
            root._clearSnapshot = {
                "ids": root.messageIDs,
                "byID": root.messageByID,
                "tokens": { "input": root.engine.tokenCount.input, "output": root.engine.tokenCount.output, "total": root.engine.tokenCount.total },
            };
            undoClearTimer.restart();
        }
        root.messageIDs = [];
        root.messageByID = ({});
        root.engine.tokenCount.input = -1;
        root.engine.tokenCount.output = -1;
        root.engine.tokenCount.total = -1;
    }

    function undoClear() {
        if (!root._clearSnapshot) return;
        root.messageByID = root._clearSnapshot.byID;
        root.messageIDs = root._clearSnapshot.ids;
        root.engine.tokenCount.input = root._clearSnapshot.tokens.input;
        root.engine.tokenCount.output = root._clearSnapshot.tokens.output;
        root.engine.tokenCount.total = root._clearSnapshot.tokens.total;
        root._clearSnapshot = null;
        undoClearTimer.stop();
    }

    readonly property Timer undoClearTimer: Timer {
        interval: 15000
        repeat: false
        onTriggered: root._clearSnapshot = null
    }

    function chatToJson() {
        return root.messageIDs.map(id => {
            const message = root.messageByID[id]
            return ({
                "role": message.role,
                "rawContent": message.rawContent,
                "fileMimeType": message.fileMimeType,
                "fileUri": message.fileUri,
                "localFilePath": message.localFilePath,
                "model": message.model,
                "thinking": false,
                "done": true,
                "annotations": message.annotations,
                "annotationSources": message.annotationSources,
                "functionName": message.functionName,
                "functionCall": message.functionCall,
                "thoughtSignature": message.thoughtSignature,
                "functionResponse": message.functionResponse,
                "visibleToUser": message.visibleToUser,
                "timestamp": message.timestamp,
            })
        })
    }

    readonly property FileView chatSaveFile: FileView {
        property string chatName: ""
        path: chatName.length > 0 ? `${Directories.aiChats}/${chatName}.json` : ""
        blockLoading: true // Prevent race conditions
    }

    /**
     * Saves chat to a JSON list of message objects.
     * @param chatName name of the chat
     */
    function saveChat(chatName) {
        chatSaveFile.chatName = chatName.trim()
        const saveContent = JSON.stringify(root.chatToJson())
        chatSaveFile.setText(saveContent)
        root.engine.refreshSavedChats();
    }

    /**
     * Loads chat from a JSON list of message objects.
     * @param chatName name of the chat
     */
    function loadChat(chatName) {
        try {
            chatSaveFile.chatName = chatName.trim()
            chatSaveFile.reload()
            const saveContent = chatSaveFile.text()
            const saveData = JSON.parse(saveContent)
            root.clearMessages(false)
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.engine.aiMessageComponent.createObject(root, {
                    "role": message.role,
                    "rawContent": message.rawContent,
                    "content": message.rawContent,
                    "fileMimeType": message.fileMimeType,
                    "fileUri": message.fileUri,
                    "localFilePath": message.localFilePath,
                    "model": message.model,
                    "thinking": message.thinking,
                    "done": message.done,
                    "annotations": message.annotations,
                    "annotationSources": message.annotationSources,
                    "functionName": message.functionName,
                    "functionCall": message.functionCall,
                    "thoughtSignature": message.thoughtSignature ?? "",
                    "functionResponse": message.functionResponse,
                    "visibleToUser": message.visibleToUser,
                    "timestamp": message.timestamp ?? 0,
                });
            }
        } catch (e) {
            console.log("[AI] Could not load chat: ", e);
        } finally {
            root.engine.refreshSavedChats();
        }
    }

    // Inject a hidden context pair into message history (#11)
    function injectContext(text) {
        const ctxU = root.engine.aiMessageComponent.createObject(root, {
            "role": "user", "content": text, "rawContent": text,
            "thinking": false, "done": true, "visibleToUser": false
        });
        root.appendMessage(ctxU);
        const ctxA = root.engine.aiMessageComponent.createObject(root, {
            "role": "assistant", "content": "Understood, I have that context.",
            "rawContent": "Understood, I have that context.",
            "thinking": false, "done": true, "visibleToUser": false
        });
        root.appendMessage(ctxA);
    }

    // Run a subtask in an isolated context; result injected back into main chat (#15)
    function spawnSubtask(description) {
        if (root._savedContext) {
            root.addMessage(Translation.tr("A subtask is already running."), root.engine.interfaceRole);
            return;
        }
        root._savedContext = {
            "messageIDs": root.messageIDs.slice(),
            "messageByID": Object.assign({}, root.messageByID),
            "tokenInput": root.engine.tokenCount.input,
            "tokenOutput": root.engine.tokenCount.output,
            "tokenTotal": root.engine.tokenCount.total
        };
        root.messageIDs = [];
        root.messageByID = ({});
        root.engine.tokenCount.input = -1;
        root.engine.tokenCount.output = -1;
        root.engine.tokenCount.total = -1;
        root.addMessage(Translation.tr("_Subtask: %1_").arg(description), root.engine.interfaceRole);
        root.engine.postResponseHook = () => {
            const lastId = root.messageIDs[root.messageIDs.length - 1];
            const lastMsg = root.messageByID[lastId];
            const resultText = (lastMsg && lastMsg.role === "assistant")
                ? lastMsg.rawContent
                : Translation.tr("(no result)");
            if (root._savedContext) {
                root.messageIDs = root._savedContext.messageIDs;
                root.messageByID = root._savedContext.messageByID;
                root.engine.tokenCount.input = root._savedContext.tokenInput;
                root.engine.tokenCount.output = root._savedContext.tokenOutput;
                root.engine.tokenCount.total = root._savedContext.tokenTotal;
                root._savedContext = null;
            }
            root.addMessage(Translation.tr("**Subtask result:**\n\n%1").arg(resultText), root.engine.interfaceRole);
        };
        root.engine.requester.sendUserMessage(description);
    }

    property bool compacting: false
    property var _compactionDone: null
    property string _queuedMessage: ""
    readonly property int compactionThreshold: Config.options?.ai?.memory?.compactionThreshold ?? 30000
    readonly property string compactionSystemPrompt:
        "You are a conversation summarizer. Produce a compact context block in exactly this format:\n\n" +
        "## Goal\n<what the user is trying to accomplish>\n\n" +
        "## Done\n<bullet list of key actions, decisions, results so far>\n\n" +
        "## State\n<what is resolved and what is still open>\n\n" +
        "## Pending\n<next steps or open questions the user or assistant must act on>\n\n" +
        "## Key Context\n<file paths, values, constraints, facts that must not be lost>\n\n" +
        "Keep the total under 1000 tokens. No preamble. No sign-off."

    function compact(onDone) {
        if (root.compacting) return;
        const msgList = root.messageIDs
            .map(id => root.messageByID[id])
            .filter(m => m.role !== root.engine.interfaceRole);
        if (msgList.length < 4) return;

        root.compacting = true;
        root._compactionDone = onDone ?? null;

        const chatText = msgList.map(m => {
            const label = m.role === "assistant" ? "ASSISTANT" : "USER";
            const body = (m.functionResponse && m.functionResponse.length > 0)
                ? `[Tool output: ${m.functionName}]\n${m.functionResponse}`
                : m.rawContent;
            return `${label}: ${body}`;
        }).join("\n\n---\n\n");

        const tmpMsg = root.engine.aiMessageComponent.createObject(root, {
            "role": "user", "content": chatText, "rawContent": chatText,
            "thinking": false, "done": true
        });
        const model = root.engine.models[root.engine.currentModelId];
        root.engine.currentApiStrategy.reset();
        const endpoint = root.engine.currentApiStrategy.buildEndpoint(model);
        const noTools = root.engine.tools[model.api_format]["none"] ?? [];
        const data = root.engine.currentApiStrategy.buildRequestData(
            model, [tmpMsg], root.compactionSystemPrompt, 0.3, noTools, "");
        const authHeader = root.engine.currentApiStrategy.buildAuthorizationHeader(root.engine.apiKeyEnvVarName);
        const scriptBody = `#!/usr/bin/env bash\ncurl --no-buffer "${endpoint}" `
            + `-H 'Content-Type: application/json' `
            + (authHeader ? `${authHeader} ` : "")
            + `--data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'` + "\n";
        const scriptContent = root.engine.currentApiStrategy.finalizeScriptContent(scriptBody);

        if (model.requires_key && root.engine.apiKeys) {
            compactor.environment[root.engine.apiKeyEnvVarName] = root.engine.apiKeys[model.key_id] ?? "";
        }
        compactor._msg = root.engine.aiMessageComponent.createObject(root, {
            "role": "assistant", "content": "", "rawContent": "",
            "thinking": false, "done": false
        });
        if (compactorScriptFile.path === "")
            compactorScriptFile.path = "/tmp/quickshell/ai/compact.sh";
        compactorScriptFile.setText(scriptContent);
        compactor.running = true;
    }

    function _applyCompaction(summaryText) {
        root.compacting = false;
        if (!summaryText || summaryText.trim().length === 0) {
            root._afterCompaction();
            return;
        }
        const keepCount = 6;
        const allIds = root.messageIDs.filter(id => root.messageByID[id].role !== root.engine.interfaceRole);
        const idsToKeep = allIds.slice(-keepCount);
        const savedMsgs = {};
        idsToKeep.forEach(id => { savedMsgs[id] = root.messageByID[id]; });
        const droppedCount = allIds.length - idsToKeep.length;

        root.messageIDs = [];
        root.messageByID = {};
        root.engine.tokenCount.input = -1;
        root.engine.tokenCount.output = -1;
        root.engine.tokenCount.total = -1;

        root.addMessage(
            `**Context compacted** — ${droppedCount} turn(s) condensed\n\n` +
            `<details><summary>Summary</summary>\n\n${summaryText}\n\n</details>`,
            root.engine.interfaceRole);

        const ctxUser = root.engine.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[Context from earlier in this conversation]\n\n${summaryText}`,
            "rawContent": `[Context from earlier in this conversation]\n\n${summaryText}`,
            "thinking": false, "done": true, "visibleToUser": false
        });
        root.appendMessage(ctxUser);

        const ctxAss = root.engine.aiMessageComponent.createObject(root, {
            "role": "assistant",
            "content": "Understood, I have the conversation context.",
            "rawContent": "Understood, I have the conversation context.",
            "thinking": false, "done": true, "visibleToUser": false
        });
        root.appendMessage(ctxAss);

        idsToKeep.forEach(id => {
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = savedMsgs[id];
        });

        if (MemoryService.ready) {
            MemoryService.remember(summaryText, "compaction", ["session", "compaction"], "system", null);
        }
        root.saveChat("lastSession");
        root._afterCompaction();
    }

    function _afterCompaction() {
        if (root._compactionDone) { root._compactionDone(); root._compactionDone = null; }
        if (root._queuedMessage.length > 0) {
            const q = root._queuedMessage;
            root._queuedMessage = "";
            Qt.callLater(() => root.engine.requester.sendUserMessage(q));
        }
    }

    readonly property FileView compactorScriptFile: FileView {
        path: ""
        blockLoading: true
        watchChanges: false
    }

    readonly property Process compactor: Process {
        command: ["bash", "/tmp/quickshell/ai/compact.sh"]
        property var _msg: null
        stdinEnabled: false

        stdout: SplitParser {
            onRead: data => {
                if (!compactor._msg || data.length === 0) return;
                try {
                    root.engine.currentApiStrategy.parseResponseLine(data, compactor._msg);
                } catch (e) {}
            }
        }
        stderr: SplitParser {
            onRead: data => console.error("[Ai:compactor]", data)
        }
        onExited: (code, status) => {
            const summary = compactor._msg ? compactor._msg.rawContent.trim() : "";
            compactor._msg = null;
            root._applyCompaction(summary);
        }
    }
}
