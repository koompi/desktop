pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.functions as CF
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.services.ai

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 *
 * This is the facade. The engine lives in `services/ai/`:
 * - ToolRegistry  - one declaration per tool, rendered per wire format
 * - ToolRunner    - dispatch, approval rules and the tool processes
 * - Conversation  - the message store, its persistence and compaction
 * - Requester     - one turn of inference, cancel, retry and the send queue
 * - ModelRegistry - model slots, inference of endpoint/format/key, discovery
 *
 * Every name the UI calls stays on this object.
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()
    signal tokenStreamed()

    readonly property ToolRegistry toolRegistry: ToolRegistry {}
    readonly property ModelRegistry modelRegistry: ModelRegistry { engine: root }
    readonly property Conversation conversation: Conversation { engine: root }
    readonly property Requester requester: Requester { engine: root }
    readonly property ToolRunner toolRunner: ToolRunner { engine: root }

    /* ---- models ---- */

    readonly property var apiKeys: modelRegistry.apiKeys
    readonly property var apiKeysLoaded: modelRegistry.apiKeysLoaded
    readonly property bool currentModelHasApiKey: modelRegistry.currentModelHasApiKey
    readonly property var models: modelRegistry.models
    readonly property var modelList: modelRegistry.modelList
    readonly property var currentModelId: modelRegistry.currentModelId
    readonly property ApiStrategy currentApiStrategy: modelRegistry.currentApiStrategy

    function safeModelName(modelName) { return modelRegistry.safeModelName(modelName); }
    function guessModelLogo(model) { return modelRegistry.guessModelLogo(model); }
    function guessModelName(model) { return modelRegistry.guessModelName(model); }
    function inferEndpointForModel(modelName) { return modelRegistry.inferEndpointForModel(modelName); }
    function inferApiFormatForModel(modelName) { return modelRegistry.inferApiFormatForModel(modelName); }
    function inferKeyIdForModel(modelName) { return modelRegistry.inferKeyIdForModel(modelName); }
    function addModel(modelName, data) { modelRegistry.addModel(modelName, data); }
    function getModel() { return modelRegistry.getModel(); }
    function setModel(modelId, feedback = true, setPersistentState = true) { modelRegistry.setModel(modelId, feedback, setPersistentState); }
    function setEndpoint(url) { modelRegistry.setEndpoint(url); }
    function refreshLitertLmModels() { modelRegistry.refreshLitertLmModels(); }
    function addApiKeyAdvice(model) { modelRegistry.addApiKeyAdvice(model); }
    function setApiKey(key) { modelRegistry.setApiKey(key); }
    function printApiKey() { modelRegistry.printApiKey(); }

    /* ---- tools ---- */

    property string currentTool: Config?.options.ai.tool ?? "search"
    readonly property var tools: toolRegistry.tools
    readonly property bool webToolsEnabled: toolRegistry.webToolsEnabled
    readonly property bool agentToolEnabled: toolRegistry.agentToolEnabled
    property list<var> availableTools: Object.keys(root.tools[root.models[root.currentModelId]?.api_format] ?? {})
    property var toolDescriptions: {
        "functions": Translation.tr("Commands, edit configs, search.\nTakes an extra turn to switch to search mode if that's needed"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }
    readonly property string toolStatusLabel: toolRunner.toolStatusLabel
    function riskOf(name) { return toolRegistry.riskOf(name); }
    function approvalOf(name) { return toolRegistry.approvalOf(name); }

    function setTool(tool) {
        if (!root.tools[root.models[root.currentModelId]?.api_format] || !(tool in root.tools[root.models[root.currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }

    function commandRule(command) { return toolRunner.commandRule(command); }
    function isPreApproved(name, args) { return toolRunner.isPreApproved(name, args); }
    function rememberApproval(name, args) { toolRunner.rememberApproval(name, args); }
    function rejectCommand(message) { toolRunner.rejectCommand(message); }
    function approveCommand(message, always) { toolRunner.approveCommand(message, always); }
    function handleFunctionCall(name, args, message) { toolRunner.handleFunctionCall(name, args, message); }

    /* ---- conversation ---- */

    readonly property var messageIDs: conversation.messageIDs
    readonly property var messageByID: conversation.messageByID
    readonly property bool canUndoClear: conversation.canUndoClear
    readonly property bool compacting: conversation.compacting
    readonly property int compactionThreshold: conversation.compactionThreshold
    readonly property int contextWindow: conversation.contextWindow
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }
    property var postResponseHook

    function idForMessage(message) { return conversation.idForMessage(message); }
    function addMessage(message, role) { conversation.addMessage(message, role); }
    function removeMessage(index) { conversation.removeMessage(index); }
    function clearMessages(snapshot = true) { conversation.clearMessages(snapshot); }
    function undoClear() { conversation.undoClear(); }
    function chatToJson() { return conversation.chatToJson(); }
    function saveChat(chatName) { conversation.saveChat(chatName); }
    function loadChat(chatName) { conversation.loadChat(chatName); }
    function injectContext(text) { conversation.injectContext(text); }
    function spawnSubtask(description) { conversation.spawnSubtask(description); }
    function compact(onDone) { conversation.compact(onDone); }

    /* ---- requests ---- */

    readonly property bool requestActive: requester.running
    property string pendingFilePath: ""
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5

    function sendUserMessage(message) { requester.sendUserMessage(message); }
    function cancelRequest() { requester.cancelRequest(); }
    function retryRequest() { requester.retryRequest(); }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= root.messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (value == NaN || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), root.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), root.interfaceRole);
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), root.interfaceRole);
    }

    /* ---- threads ---- */

    readonly property var threads: conversation.threadStore.threads
    readonly property string threadId: conversation.threadId
    readonly property string threadTitle: conversation.threadTitle

    function newThread() { return conversation.newThread(); }
    function openThread(id) { return conversation.openThread(id); }
    function renameThread(id, title) { return conversation.renameThread(id, title); }
    function deleteThread(id) { return conversation.deleteThread(id); }
    function refreshThreads() { conversation.threadStore.refresh(); }

    /* ---- feedback and corrections ---- */

    readonly property FeedbackService feedback: FeedbackService { engine: root }

    readonly property var corrections: feedback.corrections
    readonly property var openConflicts: feedback.openConflicts
    readonly property var activeSuppressions: feedback.activeSuppressions
    readonly property var trustReport: feedback.trustReport
    readonly property bool recallPaused: feedback.recallPaused

    function openCorrection(target) { feedback.openCorrection(target); }
    function closeCorrection() { feedback.closeCorrection(); }
    function correctionDraft(text, claim) { return feedback.draftFrom(text, claim); }
    function correctionProvenance(record) { return feedback.provenanceOf(record); }
    function applyCorrection(record, callback) { return feedback.applyCorrection(record, callback); }
    function sourceKey(source) { return feedback.sourceKey(source); }
    function suppressSource(source) { feedback.suppressSource(source); }
    function unsuppressSource(key) { feedback.unsuppressSource(key); }
    function isSourceSuppressed(source) { return feedback.isSourceSuppressed(source); }
    function resolveConflict(key, dropIncoming) { feedback.resolveConflict(key, dropIncoming); }
    function recalibrate() { feedback.recalibrate(); }
    function pauseRecall(days) { feedback.pauseRecall(days); }
    function resumeRecall() { feedback.resumeRecall(); }
    function saveHallucinationReport(note) { return feedback.saveHallucinationReport(note); }
    function openFeedbackPanel() { feedback.openPanel(); }

    /* ---- identity and the system prompt ---- */

    // The session id belongs to the thread, not to this singleton. Generating it here
    // gave a new one per shell start, which is how one user's history became 23
    // sessions in the episodic log.
    readonly property string sessionId: conversation.sessionId

    readonly property string aiName: `${SystemInfo.username} AI`
    readonly property string ownerName: {
        const name = Persistent.states?.ai?.ownerName ?? "";
        return name.length > 0 ? name : "unknown";
    }

    function setOwnerName(name) {
        Persistent.states.ai.ownerName = name.trim();
    }

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }

    // Formatted block of memories recalled for the current turn (auto-RAG).
    // Empty string when nothing relevant, so the prompt stays clean.
    property string recalledMemories: ""
    function formatMemories(results) {
        // A suppressed source is excluded from retrieval, not deleted, and a
        // paused recall gives the model nothing at all.
        const kept = root.feedback.filterRecall(results);
        if (!kept || kept.length === 0) return "";
        const lines = kept.map(r => `- ${r.text}`).join("\n");
        return `\n## What you remember\n${lines}\n`;
    }

    // No MemoryService touch here on purpose. It used to warm the daemon as soon
    // as this service loaded, which meant a Python venv and an embedding model
    // loading at every login, before anyone opened the panel. SidebarLeft warms
    // it when it first opens instead.
    //
    // Keep the short circuit first. Reading any property of MemoryService constructs the
    // lazy singleton and starts the daemon, which is what this guard exists to avoid,
    // and this binding evaluates at login because SidebarLeft is built eagerly.
    property bool memoryWarmed: false

    // The whole memory section of the prompt. Empty (so no claim of memory at all)
    // unless the daemon is actually enabled and ready; otherwise the model would
    // promise to remember and silently fail.
    readonly property string memoryPromptBlock: {
        const memCfg = Config.options?.ai?.memory;
        if (!memCfg?.enable || !root.memoryWarmed || !MemoryService.ready) return "";
        return "- You have long-term memory. When the user shares something durable and worth recalling later "
            + "(preferences, important facts, ongoing projects), call the `remember` function. "
            + "Don't remember trivial or one-off chatter.\n"
            + "- **A correction is not chatter.** When the user corrects you, tells you what to call them, "
            + "or tells you how they want you to behave, store it in the same turn - `set_owner_name` for a "
            + "name, `remember` with type `preference` for anything else - even if you already have a "
            + "different value. Saying you noted it without calling the function means you did not, and you "
            + "will make the same mistake tomorrow."
            + root.recalledMemories;
    }

    property var promptSubstitutions: {
        "{DISTRO}": SystemInfo.distroName,
        "{DATETIME}": `${DateTime.time}, ${DateTime.collapsedCalendarFormat}`,
        "{WINDOWCLASS}": ToplevelManager.activeToplevel?.appId ?? "Unknown",
        "{DE}": `${SystemInfo.desktopEnvironment} (${SystemInfo.windowingSystem})`,
        "{AINAME}": root.aiName,
        "{OWNER}": root.ownerName,
        "{USERNAME}": SystemInfo.username,
        "{HOSTNAME}": SystemInfo.hostname.length > 0 ? SystemInfo.hostname : "unknown",
        "{KERNEL}": SystemInfo.kernelVersion.length > 0 ? SystemInfo.kernelVersion : "unknown",
        "{BATTERY}": Battery.available
            ? `${Math.round(Battery.percentage * 100)}%${Battery.isCharging ? " (charging)" : ""}`
            : "no battery (desktop/AC)",
        "{NETWORK}": Network.ethernet
            ? "wired connection"
            : (Network.networkName.length > 0
                ? `Wi-Fi: ${Network.networkName}`
                : "disconnected"),
        "{MEMORY}": root.memoryPromptBlock
    }

    /* ---- prompt files and saved chats ---- */

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    function refreshSavedChats() {
        getSavedChats.running = true;
    }

    Process {
        id: getDefaultPrompts
        running: true
        command: ["ls", "-1", Directories.defaultAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.defaultPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.defaultAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getUserPrompts
        running: true
        command: ["ls", "-1", Directories.userAiPrompts]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.userPrompts = text.split("\n")
                    .filter(fileName => fileName.endsWith(".md") || fileName.endsWith(".txt"))
                    .map(fileName => `${Directories.userAiPrompts}/${fileName}`)
            }
        }
    }

    Process {
        id: getSavedChats
        running: true
        command: ["ls", "-1", Directories.aiChats]
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.length === 0) return;
                root.savedChats = text.split("\n")
                    .filter(fileName => fileName.endsWith(".json"))
                    .map(fileName => `${Directories.aiChats}/${fileName}`)
            }
        }
    }

    FileView {
        id: promptLoader
        watchChanges: false;
        onLoadedChanged: {
            if (!promptLoader.loaded) return;
            Config.options.ai.systemPrompt = promptLoader.text();
            root.addMessage(Translation.tr("Loaded the following system prompt\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
        }
    }

    function printPrompt() {
        root.addMessage(Translation.tr("The current system prompt is\n\n---\n\n%1").arg(Config.options.ai.systemPrompt), root.interfaceRole);
    }

    function loadPrompt(filePath) {
        promptLoader.path = "" // Unload
        promptLoader.path = filePath; // Load
        promptLoader.reload();
    }

    Component.onCompleted: {
        // Restore last session so a shell reload doesn't wipe the conversation
        if (Config.options?.ai?.restoreSession ?? true) {
            root.loadChat("lastSession");
        }
    }
}
