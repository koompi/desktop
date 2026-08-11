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
        return root._toJson(root.messageIDs, root.messageByID);
    }

    /**
     * Every field of `AiMessageData` that still means something after a restart,
     * written and read back through this one list so the two directions cannot
     * drift apart. A field missing from a stored message keeps the type's own
     * default, which is what makes older files load unchanged.
     *
     * `thinking`, `done` and `functionPending` are deliberately absent: they are
     * the state of a turn in flight, and a stored message is finished by
     * definition. Restoring `functionPending` would resume a spinner that has
     * nothing left to wait for.
     */
    readonly property var persistedFields: [
        "role", "rawContent", "fileMimeType", "fileUri", "localFilePath", "model",
        "annotations", "annotationSources", "searchQueries",
        "functionName", "functionCall", "functionResponse",
        "toolCalls", "toolCallId", "sources",
        "thoughtSignature", "visibleToUser", "timestamp",
    ]

    function _toJson(ids, byID) {
        return ids.map(id => {
            const message = byID[id];
            const stored = { "thinking": false, "done": true };
            for (let i = 0; i < root.persistedFields.length; i++) {
                const field = root.persistedFields[i];
                stored[field] = root._plain(message[field]);
            }
            return stored;
        });
    }

    // `list<string>` properties read back as a QML list, which JSON.stringify
    // renders as a string rather than an array.
    function _plain(value) {
        if (value === undefined || value === null) return value;
        if (Array.isArray(value)) return value;
        if (typeof value === "object" && typeof value.length === "number")
            return Array.prototype.slice.call(value);
        return value;
    }

    // --- threads --------------------------------------------------------

    property bool isSubtask: false

    property string chatsDirectory: Directories.aiChats

    readonly property ThreadStore threadStore: ThreadStore {
        active: !root.isSubtask
        directory: root.chatsDirectory
    }

    readonly property string sessionId: root.threadStore.sessionId
    readonly property string threadTitle: root.threadStore.currentTitle
    readonly property string threadId: root.threadStore.currentThreadId

    function newThread() {
        root.clearMessages(false);
        return root.threadStore.createThread("");
    }

    function openThread(id) {
        return root.loadChat(id);
    }

    function renameThread(id, title) {
        return root.threadStore.renameThread(id, title);
    }

    function deleteThread(id) {
        const wasCurrent = id === root.threadStore.currentThreadId;
        const removed = root.threadStore.deleteThread(id);
        if (removed && wasCurrent) root.clearMessages(false);
        if (removed) root.engine.refreshSavedChats();
        return removed;
    }

    /** What belongs in the thread file: the user's conversation, never a subtask's. */
    function _persistedMessages() {
        if (root._parked) return root._toJson(root._parked.ids, root._parked.byID);
        return root.chatToJson();
    }

    /**
     * Writes the conversation to its thread file. An empty name, or the
     * `lastSession` alias every turn still autosaves under, means the active
     * thread; any other name is a thread of its own.
     */
    function saveChat(chatName) {
        const requested = (chatName ?? "").trim();
        const id = (requested.length === 0 || requested === root.threadStore.autosaveAlias)
            ? root.threadStore.ensureCurrentThread()
            : requested;
        root.threadStore.selectThread(id);
        const messages = root._persistedMessages();
        root.threadStore.writeThread(id, messages, null);
        root.threadStore.noteSaved(id, messages.length);
        const firstUser = messages.find(m => m.role === "user"
            && (m.rawContent ?? "").length > 0 && m.visibleToUser !== false);
        if (firstUser) root.threadStore.suggestTitle(id, firstUser.rawContent);
        root.engine.refreshSavedChats();
    }

    /**
     * Replaces the conversation with a stored thread. A read that fails leaves
     * the current conversation alone — an unreadable file is not an empty chat.
     */
    function loadChat(chatName) {
        root.threadStore.ensureIndexLoaded();
        const id = root.threadStore.resolve(chatName);
        if (id.length === 0) return false;
        const stored = root.threadStore.readThread(id);
        if (!stored) {
            console.log("[AI] No conversation stored as", id, "— keeping the current one");
            root.engine.refreshSavedChats();
            return false;
        }
        root.clearMessages(false);
        const repaired = root._repairToolPairing(stored.messages);
        if (repaired > 0)
            console.log("[AI] rebuilt", repaired, "tool call pairing(s) in", id);
        const ids = [];
        const byID = ({});
        for (let i = 0; i < stored.messages.length; i++) {
            const message = stored.messages[i];
            const messageId = `${id}:${i}`;
            const props = {
                "content": message.rawContent ?? "",
                "thinking": false,
                "done": true,
                "functionPending": false,
            };
            for (let f = 0; f < root.persistedFields.length; f++) {
                const field = root.persistedFields[f];
                if (message[field] !== undefined && message[field] !== null)
                    props[field] = message[field];
            }
            byID[messageId] = root.engine.aiMessageComponent.createObject(root, props);
            ids.push(messageId);
        }
        root.messageByID = byID;
        root.messageIDs = ids;
        root.threadStore.selectThread(id);
        root.threadStore.adoptMeta(id, stored.meta);
        root.threadStore.noteLoaded(id, ids.length);
        root.engine.refreshSavedChats();
        return true;
    }

    /**
     * Every thread saved before the tool wiring was persisted comes back with a
     * role "tool" message whose call id was dropped on the way to disk, so the
     * Activity pane has nothing to match on and the result cannot find the turn
     * that asked for it. The pairing is still recoverable — the assistant turn
     * above names the function it called — so it is rebuilt on load rather than
     * left broken, and the next save writes it back properly.
     *
     * Nothing is invented: a message that already carries an id is untouched,
     * and a result with no assistant turn naming the same function is left
     * alone rather than guessed at.
     * @returns how many pairs were rebuilt
     */
    function _repairToolPairing(messages) {
        let repaired = 0;
        for (let i = 0; i < messages.length; i++) {
            const result = messages[i];
            const isResult = result.role === "tool"
                || (result.functionResponse ?? "").length > 0;
            const name = result.functionName ?? "";
            if (!isResult || name.length === 0) continue;
            if ((result.toolCallId ?? "").length > 0) continue;

            let caller = null;
            for (let j = i - 1; j >= 0; j--) {
                if (messages[j].role !== "assistant") continue;
                caller = messages[j];
                break;
            }
            if (!caller || (caller.toolCalls ?? []).length > 0) continue;
            if ((caller.functionName ?? "") !== name) continue;

            const id = `restored-${i}-${name}`;
            const call = caller.functionCall;
            caller.toolCalls = [{
                "id": id,
                "name": name,
                "arguments": JSON.stringify((call && call.args) ? call.args : (call ?? {})),
            }];
            result.toolCallId = id;
            repaired++;
        }
        return repaired;
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

    // --- subtasks -------------------------------------------------------

    // The subtask's turns belong to this object, not to the user's chat. The
    // user's messages are parked whole while it runs, so a save, a compaction
    // or a concurrent turn during a subtask can no longer write the subtask's
    // context over the thread (#15, D37).
    property Conversation subtaskConversation: null
    property var _parked: null
    property var _parkedHook: null
    readonly property bool inSubtask: root.subtaskConversation !== null

    // Created at runtime: a QML type may not name itself in its own file.
    property var subtaskComponent: null

    function _subtaskComponent() {
        if (!root.subtaskComponent)
            root.subtaskComponent = Qt.createComponent(Qt.resolvedUrl("Conversation.qml"));
        return root.subtaskComponent;
    }

    readonly property Timer subtaskWatchdog: Timer {
        interval: 300000
        repeat: false
        onTriggered: {
            if (!root.inSubtask) return;
            root._endSubtask(Translation.tr("(subtask timed out)"));
        }
    }

    onMessageIDsChanged: {
        if (root.subtaskConversation) root.subtaskConversation.messageIDs = root.messageIDs;
        root.updateTokenEstimate();
    }

    function spawnSubtask(description) {
        if (root.inSubtask) {
            root.addMessage(Translation.tr("A subtask is already running."), root.engine.interfaceRole);
            return;
        }
        const component = root._subtaskComponent();
        const sub = component.status === Component.Ready
            ? component.createObject(root, { "engine": root.engine, "isSubtask": true })
            : null;
        if (!sub) {
            root.addMessage(Translation.tr("Could not start the subtask."), root.engine.interfaceRole);
            return;
        }
        root._parked = {
            "ids": root.messageIDs.slice(),
            "byID": Object.assign({}, root.messageByID),
            "tokenInput": root.engine.tokenCount.input,
            "tokenOutput": root.engine.tokenCount.output,
            "tokenTotal": root.engine.tokenCount.total
        };
        root.messageByID = ({});
        sub.messageByID = root.messageByID;
        root.subtaskConversation = sub;
        root.messageIDs = [];
        root.engine.tokenCount.input = -1;
        root.engine.tokenCount.output = -1;
        root.engine.tokenCount.total = -1;
        root.addMessage(Translation.tr("_Subtask: %1_").arg(description), root.engine.interfaceRole);
        root._parkedHook = root.engine.postResponseHook;
        root.engine.postResponseHook = () => root._endSubtask(null);
        root.subtaskWatchdog.restart();
        root.engine.requester.sendUserMessage(description);
    }

    function _endSubtask(failure) {
        if (!root.inSubtask) return;
        root.subtaskWatchdog.stop();
        const lastId = root.messageIDs[root.messageIDs.length - 1];
        const lastMsg = root.messageByID[lastId];
        const resultText = failure ?? ((lastMsg && lastMsg.role === "assistant")
            ? lastMsg.rawContent
            : Translation.tr("(no result)"));

        root.subtaskConversation = null;
        const parked = root._parked;
        root._parked = null;
        if (parked) {
            root.messageByID = parked.byID;
            root.messageIDs = parked.ids;
            root.engine.tokenCount.input = parked.tokenInput;
            root.engine.tokenCount.output = parked.tokenOutput;
            root.engine.tokenCount.total = parked.tokenTotal;
        }
        root.engine.postResponseHook = root._parkedHook;
        root._parkedHook = null;
        root.addMessage(Translation.tr("**Subtask result:**\n\n%1").arg(resultText), root.engine.interfaceRole);
    }

    property bool compacting: false
    property var _compactionDone: null
    property string _queuedMessage: ""
    // --- context budget -------------------------------------------------

    readonly property string litertConfigPath:
        (Quickshell.env("LITERT_LM_DIR") || `${Quickshell.env("HOME")}/.litert-lm`) + "/config.json"

    readonly property FileView litertConfigFile: FileView {
        path: root.isSubtask ? "" : root.litertConfigPath
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
    }

    readonly property var litertConfig: {
        try {
            return JSON.parse(root.litertConfigFile.text());
        } catch (e) {
            return null;
        }
    }

    readonly property var currentModel: {
        const models = root.engine ? root.engine.models : null;
        if (!models) return null;
        return models[root.engine.currentModelId] ?? null;
    }

    readonly property string currentModelName: root.currentModel ? (root.currentModel.model ?? "") : ""

    readonly property string litertPort: `${Config.options?.ai?.memory?.litertPort ?? 9379}`

    readonly property bool servedByLitert:
        root.currentModel !== null && (root.currentModel.endpoint ?? "").indexOf(`:${root.litertPort}`) >= 0

    // Same merge LiteRT-LM does when it starts the model: per-model over default.
    // Whatever this says is what the server will accept, and the request is
    // rejected outright above it.
    readonly property int litertWindow: {
        const cfg = root.litertConfig;
        if (!cfg) return 0;
        const name = root.currentModelName;
        const alt = name.indexOf("/") >= 0 ? name.replace(/\//g, "--") : name.replace(/--/g, "/");
        const models = cfg.models ?? ({});
        const perModel = models[name] ?? models[alt] ?? null;
        if (perModel && perModel.max_num_tokens) return perModel.max_num_tokens;
        if (cfg.default && cfg.default.max_num_tokens) return cfg.default.max_num_tokens;
        return 0;
    }

    readonly property var modelWindows: ({
        "gemini-1.5": 1048576, "gemini-2.0": 1048576, "gemini-2.5": 1048576,
        "gpt-4o": 128000, "gpt-4.1": 1047576, "gpt-5": 400000, "o3": 200000,
        "claude": 200000, "codestral": 256000, "mistral": 128000,
        "gemma": 8192, "llama": 8192, "phi": 16384, "qwen": 32768, "deepseek": 65536,
    })

    readonly property int modelDefaultWindow: {
        const name = root.currentModelName.toLowerCase();
        if (name.length === 0) return 0;
        const keys = Object.keys(root.modelWindows);
        for (let i = 0; i < keys.length; i++)
            if (name.indexOf(keys[i]) >= 0) return root.modelWindows[keys[i]];
        return 0;
    }

    readonly property int configuredWindow: Config.options?.ai?.memory?.contextWindow ?? 0

    readonly property int contextWindow:
        (root.servedByLitert && root.litertWindow > 0) ? root.litertWindow
        : root.modelDefaultWindow > 0 ? root.modelDefaultWindow
        : root.configuredWindow > 0 ? root.configuredWindow
        : 8192

    readonly property string contextWindowSource:
        (root.servedByLitert && root.litertWindow > 0) ? `litert-lm ${root.litertConfigPath}`
        : root.modelDefaultWindow > 0 ? `model default for ${root.currentModelName}`
        : root.configuredWindow > 0 ? "Config.options.ai.memory.contextWindow"
        : "fallback"

    readonly property real compactionFraction: {
        const configured = Config.options?.ai?.memory?.compactionFraction ?? 0.6;
        return Math.min(0.95, Math.max(0.1, configured));
    }

    readonly property int derivedCompactionThreshold:
        Math.max(512, Math.floor(root.contextWindow * root.compactionFraction))

    // A configured threshold may lower the bar, never raise it past what the
    // server accepts: a number typed here outlives the model it was typed for.
    readonly property int compactionThreshold: {
        const configured = Config.options?.ai?.memory?.compactionThreshold ?? 0;
        return configured > 0
            ? Math.min(configured, root.derivedCompactionThreshold)
            : root.derivedCompactionThreshold;
    }

    // LiteRT-LM's streamed responses carry no `usage` block, so tokenCount stays
    // at -1 and a threshold on the reported number can never be crossed. This is
    // measured from what is about to be sent instead. 3.6 chars per token
    // slightly overcounts English prose, which errs towards compacting early.
    readonly property real charsPerToken: 3.6
    property int estimatedTokens: 0
    readonly property int tokensInUse: Math.max(root.engine ? root.engine.tokenCount.total : -1, root.estimatedTokens)

    function updateTokenEstimate() {
        let chars = root.engine ? (root.engine.systemPrompt ?? "").length : 0;
        for (let i = 0; i < root.messageIDs.length; i++) {
            const message = root.messageByID[root.messageIDs[i]];
            if (!message) continue;
            chars += (message.rawContent ?? "").length + (message.functionResponse ?? "").length;
        }
        root.estimatedTokens = Math.ceil(chars / root.charsPerToken);
    }

    function maybeCompact() {
        if (root.compacting || root.inSubtask) return false;
        if (root.engine && root.engine.requestActive) return false;
        if (root.tokensInUse <= root.compactionThreshold) return false;
        console.log("[AI] compacting:", root.tokensInUse, "tokens of a", root.contextWindow, "window");
        root.compact(null);
        return true;
    }

    // The turn is over and the next one has to fit: check the budget here rather
    // than after the server has already refused the request.
    readonly property Connections turnWatcher: Connections {
        target: root.engine
        enabled: !root.isSubtask
        function onRequestActiveChanged() {
            if (root.engine.requestActive) return;
            root.updateTokenEstimate();
            root.maybeCompact();
        }
    }
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
            compactorScriptFile.path = root.compactorScriptPath;
        compactorScriptFile.setText(scriptContent);
        compactor.running = true;
    }

    function _applyCompaction(summaryText) {
        root.compacting = false;
        if (!summaryText || summaryText.trim().length === 0) {
            root._afterCompaction();
            return;
        }
        // Keeping a fixed six messages made compaction *grow* the context when
        // one of them was a 35k-character paste. The tail is kept by token
        // budget instead, so what survives always fits.
        const keepCount = 6;
        const keepBudget = Math.floor(root.compactionThreshold / 2);
        const allIds = root.messageIDs.filter(id => root.messageByID[id].role !== root.engine.interfaceRole);
        const idsToKeep = [];
        let kept = Math.ceil(summaryText.length / root.charsPerToken);
        for (let i = allIds.length - 1; i >= 0 && idsToKeep.length < keepCount; i--) {
            const message = root.messageByID[allIds[i]];
            const cost = Math.ceil(((message.rawContent ?? "").length
                + (message.functionResponse ?? "").length) / root.charsPerToken);
            if (idsToKeep.length > 0 && kept + cost > keepBudget) break;
            idsToKeep.unshift(allIds[i]);
            kept += cost;
        }
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

    // The summariser's script carries the whole conversation, exactly like the
    // request body does, so it lives beside it in the user's own runtime
    // directory and is chmodded before bash reads it.
    readonly property string compactorScriptPath: `${root.engine.requester.scriptDirPath}/compact.sh`

    readonly property Process compactor: Process {
        command: ["bash", "-c", 'chmod 600 "$1" 2>/dev/null; exec bash "$1"', "--", root.compactorScriptPath]
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
