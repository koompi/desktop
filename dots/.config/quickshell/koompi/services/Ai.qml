pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common.functions as CF
import qs.modules.common
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import qs.services
import qs.services.ai

/**
 * Basic service to handle LLM chats. Supports Google's and OpenAI's API formats.
 * Supports Gemini and OpenAI models.
 * Limitations:
 * - For now functions only work with Gemini API format
 */
Singleton {
    id: root

    property Component aiMessageComponent: AiMessageData {}
    property Component aiModelComponent: AiModel {}
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}
    readonly property string interfaceRole: "interface"
    readonly property string apiKeyEnvVarName: "API_KEY"

    signal responseFinished()
    signal tokenStreamed()
    readonly property bool requestActive: requester.running

    property string systemPrompt: {
        let prompt = Config.options?.ai?.systemPrompt ?? "";
        for (let key in root.promptSubstitutions) {
            // prompt = prompt.replaceAll(key, root.promptSubstitutions[key]);
            // QML/JS doesn't support replaceAll, so use split/join
            prompt = prompt.split(key).join(root.promptSubstitutions[key]);
        }
        return prompt;
    }
    // property var messages: []
    property var messageIDs: []
    property var messageByID: ({})
    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = models[currentModelId];
        if (!model || !model.requires_key) return true;
        if (!apiKeysLoaded) return false;
        const key = apiKeys[model.key_id];
        return (key?.length > 0);
    }
    property var postResponseHook
    property real temperature: Persistent.states?.ai?.temperature ?? 0.5
    property QtObject tokenCount: QtObject {
        property int input: -1
        property int output: -1
        property int total: -1
    }

    // Dead-host cooldown (#10)
    property int _errorStreak: 0
    property bool _cooldownActive: false

    // Stop / retry / queued sends
    property bool _cancelled: false
    property bool _retryAfterCancel: false
    property var _pendingSends: []

    // Undo for clearMessages
    property var _clearSnapshot: null
    readonly property bool canUndoClear: _clearSnapshot !== null

    // Subtask context isolation slot (#15)
    property var _savedContext: null

    // Stable 6-char session ID — used for episodic log and session fork (#7, #11)
    readonly property string sessionId: (function() {
        const c = "abcdefghijklmnopqrstuvwxyz0123456789";
        let id = "";
        for (let i = 0; i < 6; i++) id += c[Math.floor(Math.random() * c.length)];
        return id;
    })()

    function idForMessage(message) {
        // Generate a unique ID using timestamp and random value
        return Date.now().toString(36) + Math.random().toString(36).substr(2, 8);
    }

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    property list<var> defaultPrompts: []
    property list<var> userPrompts: []
    property list<var> promptFiles: [...defaultPrompts, ...userPrompts]
    property list<var> savedChats: []

    readonly property string aiName: `${SystemInfo.username} AI`
    readonly property string ownerName: {
        const name = Persistent.states?.ai?.ownerName ?? "";
        return name.length > 0 ? name : "unknown";
    }

    // Touching MemoryService here forces the singleton (and its daemon) to start
    // warming as soon as the AI service loads, instead of lazily on first recall.
    readonly property bool memoryReady: MemoryService.ready

    // Early context compaction ─────────────────────────────────────────────
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
            .filter(m => m.role !== root.interfaceRole);
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

        const tmpMsg = root.aiMessageComponent.createObject(root, {
            "role": "user", "content": chatText, "rawContent": chatText,
            "thinking": false, "done": true
        });
        const model = root.models[root.currentModelId];
        root.currentApiStrategy.reset();
        const endpoint = root.currentApiStrategy.buildEndpoint(model);
        const noTools = root.tools[model.api_format]["none"] ?? [];
        const data = root.currentApiStrategy.buildRequestData(
            model, [tmpMsg], root.compactionSystemPrompt, 0.3, noTools, "");
        const authHeader = root.currentApiStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
        const scriptBody = `#!/usr/bin/env bash\ncurl --no-buffer "${endpoint}" `
            + `-H 'Content-Type: application/json' `
            + (authHeader ? `${authHeader} ` : "")
            + `--data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'` + "\n";
        const scriptContent = root.currentApiStrategy.finalizeScriptContent(scriptBody);

        if (model.requires_key && root.apiKeys) {
            compactor.environment[root.apiKeyEnvVarName] = root.apiKeys[model.key_id] ?? "";
        }
        compactor._msg = root.aiMessageComponent.createObject(root, {
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
            _afterCompaction();
            return;
        }
        const keepCount = 6;
        const allIds = root.messageIDs.filter(id => root.messageByID[id].role !== root.interfaceRole);
        const idsToKeep = allIds.slice(-keepCount);
        const savedMsgs = {};
        idsToKeep.forEach(id => { savedMsgs[id] = root.messageByID[id]; });
        const droppedCount = allIds.length - idsToKeep.length;

        root.messageIDs = [];
        root.messageByID = {};
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;

        root.addMessage(
            `**Context compacted** — ${droppedCount} turn(s) condensed\n\n` +
            `<details><summary>Summary</summary>\n\n${summaryText}\n\n</details>`,
            root.interfaceRole);

        const ctxUser = root.aiMessageComponent.createObject(root, {
            "role": "user",
            "content": `[Context from earlier in this conversation]\n\n${summaryText}`,
            "rawContent": `[Context from earlier in this conversation]\n\n${summaryText}`,
            "thinking": false, "done": true, "visibleToUser": false
        });
        const uid = root.idForMessage(ctxUser);
        root.messageIDs = [...root.messageIDs, uid];
        root.messageByID[uid] = ctxUser;

        const ctxAss = root.aiMessageComponent.createObject(root, {
            "role": "assistant",
            "content": "Understood, I have the conversation context.",
            "rawContent": "Understood, I have the conversation context.",
            "thinking": false, "done": true, "visibleToUser": false
        });
        const aid = root.idForMessage(ctxAss);
        root.messageIDs = [...root.messageIDs, aid];
        root.messageByID[aid] = ctxAss;

        idsToKeep.forEach(id => {
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = savedMsgs[id];
        });

        if (MemoryService.ready) {
            MemoryService.remember(summaryText, "compaction", ["session", "compaction"], "system", null);
        }
        root.saveChat("lastSession");
        _afterCompaction();
    }

    function _afterCompaction() {
        if (root._compactionDone) { root._compactionDone(); root._compactionDone = null; }
        if (root._queuedMessage.length > 0) {
            const q = root._queuedMessage;
            root._queuedMessage = "";
            Qt.callLater(() => root.sendUserMessage(q));
        }
    }

    // Formatted block of memories recalled for the current turn (auto-RAG).
    // Empty string when nothing relevant, so the prompt stays clean.
    property string recalledMemories: ""
    function formatMemories(results) {
        if (!results || results.length === 0) return "";
        const lines = results.map(r => `- ${r.text}`).join("\n");
        return `\n## What you remember\n${lines}\n`;
    }

    // The whole memory section of the prompt. Empty (so no claim of memory at all)
    // unless the daemon is actually enabled and ready; otherwise the model would
    // promise to remember and silently fail.
    readonly property string memoryPromptBlock: {
        const memCfg = Config.options?.ai?.memory;
        if (!memCfg?.enable || !MemoryService.ready) return "";
        return "- You have long-term memory. When the user shares something durable and worth recalling later "
            + "(preferences, important facts, ongoing projects), call the `remember` function. "
            + "Don't remember trivial or one-off chatter."
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

    // Gemini: https://ai.google.dev/gemini-api/docs/function-calling
    // OpenAI: https://platform.openai.com/docs/guides/function-calling
    property string currentTool: Config?.options.ai.tool ?? "search"
    property var tools: {
        "gemini": {
            "functions": [{"functionDeclarations": [
                {
                    "name": "switch_to_search_mode",
                    "description": "Search the web",
                },
                {
                    "name": "get_shell_config",
                    "description": "Get the desktop shell config file contents",
                },
                {
                    "name": "set_shell_config",
                    "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "key": {
                                "type": "string",
                                "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                            },
                            "value": {
                                "type": "string",
                                "description": "The value to set, e.g. `true`"
                            }
                        },
                        "required": ["key", "value"]
                    }
                },
                {
                    "name": "run_shell_command",
                    "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "command": {
                                "type": "string",
                                "description": "The bash command to run",
                            },
                        },
                        "required": ["command"]
                    }
                },
                {
                    "name": "set_owner_name",
                    "description": "Remember the name the user wants to be called. Call this as soon as the user tells you their name, so you can address them properly in this and future conversations.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "name": {
                                "type": "string",
                                "description": "The name the user wants to be called, e.g. `Alice`",
                            },
                        },
                        "required": ["name"]
                    }
                },
                {
                    "name": "remember",
                    "description": "Store a durable fact in long-term memory for future conversations. Use for preferences, important personal facts, and ongoing projects — not trivial chatter.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "text": {
                                "type": "string",
                                "description": "The fact to remember, as a self-contained sentence, e.g. `The user prefers dark mode`",
                            },
                            "type": {
                                "type": "string",
                                "description": "One of: profile, preference, fact, task",
                            },
                        },
                        "required": ["text"]
                    }
                },
                {
                    "name": "recall",
                    "description": "Search long-term memory for facts relevant to a query. Use when you need to remember something about the user that isn't already in the context.",
                    "parameters": {
                        "type": "object",
                        "properties": {
                            "query": {
                                "type": "string",
                                "description": "What to look up, e.g. `user's editor preferences`",
                            },
                        },
                        "required": ["query"]
                    }
                },
            ]}],
            "search": [{
                "google_search": {}
            }],
            "none": []
        },
        "openai": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": { "type": "object", "properties": {} }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_owner_name",
                        "description": "Remember the name the user wants to be called. Call this as soon as the user tells you their name, so you can address them properly in this and future conversations.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "name": {
                                    "type": "string",
                                    "description": "The name the user wants to be called, e.g. `Alice`",
                                },
                            },
                            "required": ["name"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "remember",
                        "description": "Store a durable fact in long-term memory for future conversations. Use for preferences, important personal facts, and ongoing projects — not trivial chatter.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "text": {
                                    "type": "string",
                                    "description": "The fact to remember, as a self-contained sentence, e.g. `The user prefers dark mode`",
                                },
                                "type": {
                                    "type": "string",
                                    "description": "One of: profile, preference, fact, task",
                                },
                            },
                            "required": ["text"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "recall",
                        "description": "Search long-term memory for facts relevant to a query. Use when you need to remember something about the user that isn't already in the context.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": "What to look up, e.g. `user's editor preferences`",
                                },
                            },
                            "required": ["query"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        },
        "mistral": {
            "functions": [
                {
                    "type": "function",
                    "function": {
                        "name": "get_shell_config",
                        "description": "Get the desktop shell config file contents",
                        "parameters": { "type": "object", "properties": {} }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_shell_config",
                        "description": "Set a field in the desktop graphical shell config file. Must only be used after `get_shell_config`.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "key": {
                                    "type": "string",
                                    "description": "The key to set, e.g. `bar.borderless`. MUST NOT BE GUESSED, use `get_shell_config` to see what keys are available before setting.",
                                },
                                "value": {
                                    "type": "string",
                                    "description": "The value to set, e.g. `true`"
                                }
                            },
                            "required": ["key", "value"]
                        }
                    }
                },
                {
                    "type": "function",
                    "function": {
                        "name": "run_shell_command",
                        "description": "Run a shell command in bash and get its output. Use this only for quick commands that don't require user interaction. For commands that require interaction, ask the user to run manually instead.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "command": {
                                    "type": "string",
                                    "description": "The bash command to run",
                                },
                            },
                            "required": ["command"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "set_owner_name",
                        "description": "Remember the name the user wants to be called. Call this as soon as the user tells you their name, so you can address them properly in this and future conversations.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "name": {
                                    "type": "string",
                                    "description": "The name the user wants to be called, e.g. `Alice`",
                                },
                            },
                            "required": ["name"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "remember",
                        "description": "Store a durable fact in long-term memory for future conversations. Use for preferences, important personal facts, and ongoing projects — not trivial chatter.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "text": {
                                    "type": "string",
                                    "description": "The fact to remember, as a self-contained sentence, e.g. `The user prefers dark mode`",
                                },
                                "type": {
                                    "type": "string",
                                    "description": "One of: profile, preference, fact, task",
                                },
                            },
                            "required": ["text"]
                        }
                    },
                },
                {
                    "type": "function",
                    "function": {
                        "name": "recall",
                        "description": "Search long-term memory for facts relevant to a query. Use when you need to remember something about the user that isn't already in the context.",
                        "parameters": {
                            "type": "object",
                            "properties": {
                                "query": {
                                    "type": "string",
                                    "description": "What to look up, e.g. `user's editor preferences`",
                                },
                            },
                            "required": ["query"]
                        }
                    },
                },
            ],
            "search": [],
            "none": [],
        }
    }
    property list<var> availableTools: Object.keys(root.tools[models[currentModelId]?.api_format] ?? {})
    property var toolDescriptions: {
        "functions": Translation.tr("Commands, edit configs, search.\nTakes an extra turn to switch to search mode if that's needed"),
        "search": Translation.tr("Gives the model search capabilities (immediately)"),
        "none": Translation.tr("Disable tools")
    }

    function inferEndpointForModel(modelName) {
        const m = modelName.toLowerCase();
        if (m.includes("/")) return "https://openrouter.ai/api/v1/chat/completions";
        if (m.startsWith("gemini") || m.startsWith("gemma"))
            return `https://generativelanguage.googleapis.com/v1beta/models/${modelName}:streamGenerateContent`;
        if (m.startsWith("mistral") || m.startsWith("codestral") || m.startsWith("devstral"))
            return "https://api.mistral.ai/v1/chat/completions";
        if (m.startsWith("gpt") || m.startsWith("o1") || m.startsWith("o3") || m.startsWith("o4"))
            return "https://api.openai.com/v1/chat/completions";
        if (m.startsWith("deepseek"))
            return "https://api.deepseek.com/chat/completions";
        if (m.startsWith("kimi") || m.startsWith("moonshot"))
            return "https://api.moonshot.ai/v1/chat/completions";
        if (m.startsWith("glm"))
            return "https://api.z.ai/api/paas/v4/chat/completions";
        if (m.startsWith("minimax"))
            return "https://api.minimax.io/v1/chat/completions";
        return "https://api.openai.com/v1/chat/completions";
    }

    function inferApiFormatForModel(modelName) {
        const m = modelName.toLowerCase();
        if (m.includes("/")) return "openai";
        if (m.startsWith("gemini") || m.startsWith("gemma")) return "gemini";
        if (m.startsWith("mistral") || m.startsWith("codestral") || m.startsWith("devstral")) return "mistral";
        return "openai";
    }

    function inferKeyIdForModel(modelName) {
        const m = modelName.toLowerCase();
        if (m.includes("/")) return "openrouter";
        if (m.startsWith("gemini") || m.startsWith("gemma")) return "gemini";
        if (m.startsWith("mistral") || m.startsWith("codestral") || m.startsWith("devstral")) return "mistral";
        if (m.startsWith("gpt") || m.startsWith("o1") || m.startsWith("o3") || m.startsWith("o4")) return "openai";
        if (m.startsWith("deepseek")) return "deepseek";
        if (m.startsWith("kimi") || m.startsWith("moonshot")) return "moonshot";
        if (m.startsWith("glm")) return "zai";
        if (m.startsWith("minimax")) return "minimax";
        return "custom";
    }

    AiModel {
        id: remoteModelObj
        model: Persistent.states?.ai?.remoteModel ?? "gemini-2.5-flash"
        name: model
        icon: root.guessModelLogo(model)
        description: Translation.tr("Remote | %1").arg(model)
        endpoint: {
            const stored = Persistent.states?.ai?.remoteEndpoint ?? "";
            return stored.length > 0 ? stored : root.inferEndpointForModel(model);
        }
        requires_key: !endpoint.includes("localhost") && !endpoint.includes("127.0.0.1")
        key_id: root.inferKeyIdForModel(model)
        api_format: {
            const stored = Persistent.states?.ai?.remoteFormat ?? "";
            return stored.length > 0 ? stored : root.inferApiFormatForModel(model);
        }
    }

    AiModel {
        id: localModelObj
        model: Persistent.states?.ai?.localModel ?? ""
        name: model.length > 0 ? root.guessModelName(model) : Translation.tr("Local (not set)")
        icon: root.guessModelLogo(model)
        description: Translation.tr("Local | %1 | %2").arg(endpoint).arg(model.length > 0 ? model : "?")
        endpoint: Persistent.states?.ai?.localEndpoint ?? "http://localhost:11434/v1/chat/completions"
        requires_key: false
        api_format: "openai"
    }

    property var models: Config.options.policies.ai === 2
        ? { "local": localModelObj }
        : { "remote": remoteModelObj, "local": localModelObj }
    property var modelList: Object.keys(root.models)
    property var currentModelId: {
        const stored = Persistent.states?.ai?.model ?? "";
        if (stored in models) return stored;
        return "remote" in models ? "remote" : "local";
    }

    property var apiStrategies: {
        "openai": openaiApiStrategy.createObject(this),
        "gemini": geminiApiStrategy.createObject(this),
        "mistral": mistralApiStrategy.createObject(this),
    }
    property ApiStrategy currentApiStrategy: apiStrategies[models[currentModelId]?.api_format || "openai"]

    property string requestScriptFilePath: "/tmp/quickshell/ai/request.sh"
    property string pendingFilePath: ""

    Component.onCompleted: {
        // Migrate: old state may have a model ID like "gemini-2.5-flash" that no
        // longer exists as a key in models{}. Treat it as a remote model name.
        const stored = Persistent.states?.ai?.model ?? "";
        if (stored !== "remote" && stored !== "local" && stored.length > 0) {
            if (modelList.indexOf(stored) === -1) {
                Persistent.states.ai.remoteModel = stored;
                Persistent.states.ai.model = "remote";
            }
        }
        setModel(currentModelId, false, false);

        // Restore last session so a shell reload doesn't wipe the conversation
        if (Config.options?.ai?.restoreSession ?? true) {
            root.loadChat("lastSession");
        }
    }

    function guessModelLogo(model) {
        const m = model.toLowerCase();
        if (m.includes("/")) return "openrouter-symbolic";
        if (m.startsWith("gemini") || m.startsWith("gemma")) return "google-gemini-symbolic";
        if (m.includes("deepseek")) return "deepseek-symbolic";
        if (m.startsWith("mistral") || m.startsWith("codestral") || m.startsWith("devstral")) return "mistral-symbolic";
        if (m.startsWith("gpt") || m.startsWith("o1") || m.startsWith("o3") || m.startsWith("o4")) return "openai-symbolic";
        if (m.startsWith("kimi") || m.startsWith("moonshot")) return "spark-symbolic";
        if (m.startsWith("glm") || m.startsWith("minimax")) return "spark-symbolic";
        if (m.includes("llama") || m.includes("gemma") || m.includes("qwen") || m.includes("phi")) return "ollama-symbolic";
        if (/^phi\d*:/i.test(model)) return "microsoft-symbolic";
        return "ollama-symbolic";
    }

    function guessModelName(model) {
        const replaced = model.replace(/-/g, ' ').replace(/:/g, ' ');
        let words = replaced.split(' ');
        words[words.length - 1] = words[words.length - 1].replace(/(\d+)b$/, (_, num) => `${num}B`)
        words = words.map((word) => {
            return (word.charAt(0).toUpperCase() + word.slice(1))
        });
        if (words[words.length - 1] === "Latest") words.pop();
        else words[words.length - 1] = `(${words[words.length - 1]})`; // Surround the last word with square brackets
        const result = words.join(' ');
        return result;
    }

    function addModel(modelName, data) {
        root.models = Object.assign({}, root.models, {
            [modelName]: aiModelComponent.createObject(this, data)
        });
        // The Ollama Process imperatively reassigns modelList, breaking its binding
        // to models. Keep them in sync here so config extraModels (added async, after
        // that reassignment) still reach the picker regardless of load order.
        root.modelList = Object.keys(root.models);
    }

    Process {
        id: getOllamaModels
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    root.modelList = [...root.modelList, ...dataJson];
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": guessModelName(model),
                            "icon": guessModelLogo(model),
                            "description": Translation.tr("Local Ollama model | %1").arg(model),
                            "homepage": `https://ollama.com/library/${model}`,
                            "endpoint": "http://localhost:11434/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                        })
                    });

                    root.modelList = Object.keys(root.models);

                } catch (e) {
                    console.log("Could not fetch Ollama models:", e);
                }
            }
        }
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

    function addMessage(message, role) {
        if (message.length === 0) return;
        const aiMessage = aiMessageComponent.createObject(root, {
            "role": role,
            "content": message,
            "rawContent": message,
            "thinking": false,
            "done": true,
            "timestamp": Date.now(),
        });
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function removeMessage(index) {
        if (index < 0 || index >= messageIDs.length) return;
        const id = root.messageIDs[index];
        root.messageIDs.splice(index, 1);
        root.messageIDs = [...root.messageIDs];
        delete root.messageByID[id];
    }

    function addApiKeyAdvice(model) {
        root.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"), 
            Ai.interfaceRole
        );
    }

    function getModel() {
        return models[currentModelId];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        if (!modelId) modelId = ""
        modelId = modelId.toLowerCase()

        // "local:<name>" — set local model name and switch to local slot
        if (modelId.startsWith("local:")) {
            const localName = modelId.slice(6).trim();
            if (setPersistentState) {
                Persistent.states.ai.localModel = localName;
                Persistent.states.ai.model = "local";
            }
            if (feedback) root.addMessage(
                Translation.tr("Local model set to **%1**\n\nEndpoint: %2").arg(localName).arg(localModelObj.endpoint),
                root.interfaceRole
            );
            return;
        }

        // "local" — switch to local slot
        if (modelId === "local") {
            if (setPersistentState) Persistent.states.ai.model = "local";
            if (feedback) root.addMessage(
                localModelObj.model.length > 0
                    ? Translation.tr("Switched to local model: **%1**").arg(localModelObj.model)
                    : Translation.tr("Switched to local slot. Set model with `/model local:NAME`"),
                root.interfaceRole
            );
            return;
        }

        // Ollama auto-discovered models (any key other than "remote"/"local")
        if (modelId !== "remote" && modelList.indexOf(modelId) !== -1) {
            const model = models[modelId];
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.addMessage(Translation.tr("Model set to %1").arg(model.name), root.interfaceRole);
            return;
        }

        // "remote" or any unrecognised name — treat as remote model name
        if (Config.options.policies.ai === 2) {
            root.addMessage(
                Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                root.interfaceRole
            );
            return;
        }

        const newRemoteModel = (modelId === "remote")
            ? (Persistent.states?.ai?.remoteModel ?? "gemini-2.5-flash")
            : modelId;
        if (setPersistentState) {
            Persistent.states.ai.remoteModel = newRemoteModel;
            Persistent.states.ai.model = "remote";
            if (modelId !== "remote") {
                Persistent.states.ai.remoteEndpoint = "";
                Persistent.states.ai.remoteFormat = "";
            }
        }
        if (feedback) root.addMessage(Translation.tr("Remote model set to **%1**").arg(newRemoteModel), root.interfaceRole);
        if (remoteModelObj.requires_key) {
            if (root.apiKeysLoaded && (!root.apiKeys[remoteModelObj.key_id] || root.apiKeys[remoteModelObj.key_id].length === 0)) {
                root.addApiKeyAdvice(remoteModelObj);
            }
        }
    }

    function setEndpoint(url) {
        if (!url || url.trim().length === 0) {
            root.addMessage(
                Translation.tr("Remote endpoint: **%1**\n\nLocal endpoint: **%2**\n\nChange with `/endpoint remote URL` or `/endpoint local URL`")
                    .arg(remoteModelObj.endpoint).arg(localModelObj.endpoint),
                root.interfaceRole
            );
            return;
        }
        url = url.trim();
        if (url.startsWith("remote ")) {
            Persistent.states.ai.remoteEndpoint = url.slice(7).trim();
            root.addMessage(Translation.tr("Remote endpoint set to **%1**").arg(Persistent.states.ai.remoteEndpoint), root.interfaceRole);
        } else if (url.startsWith("local ")) {
            Persistent.states.ai.localEndpoint = url.slice(6).trim();
            root.addMessage(Translation.tr("Local endpoint set to **%1**").arg(Persistent.states.ai.localEndpoint), root.interfaceRole);
        } else if (url === "reset") {
            Persistent.states.ai.remoteEndpoint = "";
            root.addMessage(Translation.tr("Remote endpoint reset to auto-infer"), root.interfaceRole);
        } else {
            Persistent.states.ai.remoteEndpoint = url;
            root.addMessage(Translation.tr("Remote endpoint set to **%1**").arg(url), root.interfaceRole);
        }
    }

    function setTool(tool) {
        if (!root.tools[models[currentModelId]?.api_format] || !(tool in root.tools[models[currentModelId]?.api_format])) {
            root.addMessage(Translation.tr("Invalid tool. Supported tools:\n- %1").arg(root.availableTools.join("\n- ")), root.interfaceRole);
            return false;
        }
        Config.options.ai.tool = tool;
        return true;
    }
    
    function getTemperature() {
        return root.temperature;
    }

    function setTemperature(value) {
        if (value == NaN || value < 0 || value > 2) {
            root.addMessage(Translation.tr("Temperature must be between 0 and 2"), Ai.interfaceRole);
            return;
        }
        Persistent.states.ai.temperature = value;
        root.temperature = value;
        root.addMessage(Translation.tr("Temperature set to %1").arg(value), Ai.interfaceRole);
    }

    function setApiKey(key) {
        const model = models[currentModelId];
        if (!model.requires_key) {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            const model = models[currentModelId];
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.addMessage(Translation.tr("API key set for %1").arg(model.name), Ai.interfaceRole);
    }

    function printApiKey() {
        const model = models[currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                const masked = key.length > 8 ? `${key.slice(0, 4)}…${key.slice(-4)}` : "••••";
                root.addMessage(Translation.tr("API key: `%1` (masked)").arg(masked), Ai.interfaceRole);
            } else {
                root.addMessage(Translation.tr("No API key set for %1").arg(model.name), Ai.interfaceRole);
            }
        } else {
            root.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), Ai.interfaceRole);
        }
    }

    function printTemperature() {
        root.addMessage(Translation.tr("Temperature: %1").arg(root.temperature), Ai.interfaceRole);
    }

    function clearMessages(snapshot = true) {
        if (snapshot && root.messageIDs.length > 0) {
            root._clearSnapshot = {
                "ids": root.messageIDs,
                "byID": root.messageByID,
                "tokens": { "input": root.tokenCount.input, "output": root.tokenCount.output, "total": root.tokenCount.total },
            };
            undoClearTimer.restart();
        }
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
    }

    function undoClear() {
        if (!root._clearSnapshot) return;
        root.messageByID = root._clearSnapshot.byID;
        root.messageIDs = root._clearSnapshot.ids;
        root.tokenCount.input = root._clearSnapshot.tokens.input;
        root.tokenCount.output = root._clearSnapshot.tokens.output;
        root.tokenCount.total = root._clearSnapshot.tokens.total;
        root._clearSnapshot = null;
        undoClearTimer.stop();
    }

    Timer {
        id: undoClearTimer
        interval: 15000
        repeat: false
        onTriggered: root._clearSnapshot = null
    }

    FileView {
        id: requesterScriptFile
    }

    Process {
        id: requester
        property list<string> baseCommand: ["bash"]
        property AiMessageData message
        property ApiStrategy currentStrategy

        function markDone() {
            requester.message.done = true;
            if (root.postResponseHook) {
                root.postResponseHook();
                root.postResponseHook = null;
            }
            root.saveChat("lastSession");
            root.responseFinished();
            // Append assistant turn to episodic log (#7)
            if (MemoryService.ready) {
                const evContent = requester.message.rawContent;
                if (evContent && evContent.trim().length > 0 && !requester.message.functionCall) {
                    MemoryService.appendEvent(root.sessionId, "assistant", evContent, []);
                }
            }
            // Use classify_step to decide compaction (#8)
            const decision = root.classify_step();
            if (!root.compacting && (decision === "compact_then_continue" || root.tokenCount.total > root.compactionThreshold)) {
                root.compact(null);
            }
        }

        function makeRequest() {
            const model = models[currentModelId];

            // Fetch API keys if needed
            if (model?.requires_key && !KeyringStorage.loaded) KeyringStorage.fetchKeyringData();
            
            requester.currentStrategy = root.currentApiStrategy;
            requester.currentStrategy.reset(); // Reset strategy state

            /* Put API key in environment variable */
            if (model.requires_key) requester.environment[`${root.apiKeyEnvVarName}`] = root.apiKeys ? (root.apiKeys[model.key_id] ?? "") : ""

            /* Build endpoint, request data */
            const endpoint = root.currentApiStrategy.buildEndpoint(model);
            const messageArray = root.messageIDs.map(id => root.messageByID[id]);
            const filteredMessageArray = messageArray.filter(message => message.role !== Ai.interfaceRole);
            const data = root.currentApiStrategy.buildRequestData(model, filteredMessageArray, root.systemPrompt, root.temperature, root.tools[model.api_format][root.currentTool], root.pendingFilePath);
            // console.log("[Ai] Request data: ", JSON.stringify(data, null, 2));

            let requestHeaders = {
                "Content-Type": "application/json",
            }
            
            /* Create local message object */
            requester.message = root.aiMessageComponent.createObject(root, {
                "role": "assistant",
                "model": currentModelId,
                "content": "",
                "rawContent": "",
                "thinking": true,
                "done": false,
                "timestamp": Date.now(),
            });
            const id = idForMessage(requester.message);
            root.messageIDs = [...root.messageIDs, id];
            root.messageByID[id] = requester.message;

            /* Build header string for curl */ 
            let headerString = Object.entries(requestHeaders)
                .filter(([k, v]) => v && v.length > 0)
                .map(([k, v]) => `-H '${k}: ${v}'`)
                .join(' ');

            // console.log("Request headers: ", JSON.stringify(requestHeaders));
            // console.log("Header string: ", headerString);

            /* Get authorization header from strategy */
            const authHeader = requester.currentStrategy.buildAuthorizationHeader(root.apiKeyEnvVarName);
            
            /* Script shebang */
            const scriptShebang = "#!/usr/bin/env bash\n";

            /* Create extra setup when there's an attached file */
            let scriptFileSetupContent = ""
            if (root.pendingFilePath && root.pendingFilePath.length > 0) {
                requester.message.localFilePath = root.pendingFilePath;
                scriptFileSetupContent = requester.currentStrategy.buildScriptFileSetup(root.pendingFilePath);
                root.pendingFilePath = ""
            }

            /* Create command string */
            let scriptRequestContent = ""
            scriptRequestContent += `curl --no-buffer "${endpoint}"`
                + ` ${headerString}`
                + (authHeader ? ` ${authHeader}` : "")
                + ` --data '${CF.StringUtils.shellSingleQuoteEscape(JSON.stringify(data))}'`
                + "\n"
            
            /* Send the request */
            const scriptContent = requester.currentStrategy.finalizeScriptContent(scriptShebang + scriptFileSetupContent + scriptRequestContent)
            const shellScriptPath = CF.FileUtils.trimFileProtocol(root.requestScriptFilePath)
            requesterScriptFile.path = Qt.resolvedUrl(shellScriptPath)
            requesterScriptFile.setText(scriptContent)
            requester.command = baseCommand.concat([shellScriptPath]);
            requester.running = true
        }

        stdout: SplitParser {
            onRead: data => {
                if (data.length === 0) return;
                root.tokenStreamed()
                if (requester.message.thinking) requester.message.thinking = false;
                // console.log("[Ai] Raw response line: ", data);

                // Handle response line
                try {
                    const result = requester.currentStrategy.parseResponseLine(data, requester.message);
                    // console.log("[Ai] Parsed response result: ", JSON.stringify(result, null, 2));

                    if (result.functionCall) {
                        requester.message.functionCall = result.functionCall;
                        root.handleFunctionCall(result.functionCall.name, result.functionCall.args, requester.message);
                    }
                    if (result.tokenUsage) {
                        root.tokenCount.input = result.tokenUsage.input;
                        root.tokenCount.output = result.tokenUsage.output;
                        root.tokenCount.total = result.tokenUsage.total;
                    }
                    if (result.finished) {
                        requester.markDone();
                    }
                    
                } catch (e) {
                    console.log("[AI] Could not parse response: ", e);
                    requester.message.rawContent += data;
                    requester.message.content += data;
                }
            }
        }

        onExited: (exitCode, exitStatus) => {
            const result = requester.currentStrategy.onRequestFinished(requester.message);

            if (result.finished) {
                requester.markDone();
            } else if (!requester.message.done) {
                requester.markDone();
            }

            if (root._cancelled) {
                // User stopped the response — not an error
                root._cancelled = false;
                if (root._retryAfterCancel) {
                    root._retryAfterCancel = false;
                    // Drop the stalled assistant message and re-request with the same context
                    const lastIdx = root.messageIDs.length - 1;
                    const lastMsg = root.messageByID[root.messageIDs[lastIdx]];
                    if (lastMsg && lastMsg.role === "assistant") root.removeMessage(lastIdx);
                    requester.makeRequest();
                } else if (root._pendingSends.length > 0) {
                    const next = root._pendingSends[0];
                    root._pendingSends = root._pendingSends.slice(1);
                    Qt.callLater(() => root.sendUserMessage(next));
                }
                return;
            }

            // Handle error responses
            if (requester.message.content.includes("API key not valid")) {
                root.addApiKeyAdvice(models[requester.message.model]);
            }

            // Dead-host cooldown (#10): track consecutive failures
            const isError = exitCode !== 0 || requester.message.rawContent.trim().length === 0;
            if (isError) {
                root._errorStreak++;
                if (root._errorStreak >= 2) {
                    root._cooldownActive = true;
                    cooldownTimer.restart();
                }
            } else {
                root._errorStreak = 0;
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
        if (!requester.running) return;
        root._cancelled = true;
        requester.running = false;
    }

    function retryRequest() {
        if (requester.running) {
            root._retryAfterCancel = true;
            root.cancelRequest();
        } else {
            requester.makeRequest();
        }
    }

    function sendUserMessage(message) {
        if (message.length === 0) return;
        if (root.requestActive) {
            root._pendingSends = [...root._pendingSends, message];
            root.addMessage(Translation.tr("Queued — will send when the current response finishes."), root.interfaceRole);
            return;
        }
        if (root._cooldownActive) {
            root.addMessage(Translation.tr("API is unavailable. Retrying automatically in 20 seconds."), root.interfaceRole);
            return;
        }
        if (root.compacting) {
            root._queuedMessage = message;
            root.addMessage("Compacting context… your message will send when done.", root.interfaceRole);
            return;
        }
        root.addMessage(message, "user");
        root.saveChat("lastSession");

        // Auto-RAG: pull relevant long-term memories before asking the model.
        // MemoryService guarantees the callback fires (timeout -> null), so the
        // request is never blocked by the memory daemon.
        const memCfg = Config.options?.ai?.memory;
        if (memCfg?.enable && memCfg?.autoRecall && MemoryService.ready) {
            MemoryService.recall(message, memCfg.recallCount, results => {
                root.recalledMemories = root.formatMemories(results);
                requester.makeRequest();
            });
        } else {
            root.recalledMemories = "";
            requester.makeRequest();
        }
    }

    function attachFile(filePath: string) {
        root.pendingFilePath = CF.FileUtils.trimFileProtocol(filePath);
    }

    function regenerate(messageIndex) {
        if (messageIndex < 0 || messageIndex >= messageIDs.length) return;
        const id = root.messageIDs[messageIndex];
        const message = root.messageByID[id];
        if (message.role !== "assistant") return;
        // Remove all messages after this one
        for (let i = root.messageIDs.length - 1; i >= messageIndex; i--) {
            root.removeMessage(i);
        }
        requester.makeRequest();
    }

    function createFunctionOutputMessage(name, output, includeOutputInChat = true) {
        return aiMessageComponent.createObject(root, {
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

    function addFunctionOutputMessage(name, output) {
        const aiMessage = createFunctionOutputMessage(name, output);
        const id = idForMessage(aiMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = aiMessage;
    }

    function rejectCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"
        addFunctionOutputMessage(message.functionName, Translation.tr("Command rejected by user"))
    }

    function approveCommand(message: AiMessageData) {
        if (!message.functionPending) return;
        message.functionPending = false; // User decided, no more "thinking"

        const responseMessage = createFunctionOutputMessage(message.functionName, "", false);
        const id = idForMessage(responseMessage);
        root.messageIDs = [...root.messageIDs, id];
        root.messageByID[id] = responseMessage;

        commandExecutionProc.message = responseMessage;
        commandExecutionProc.baseMessageContent = responseMessage.content;
        commandExecutionProc.shellCommand = message.functionCall.args.command;
        commandExecutionProc.running = true; // Start the command execution
    }

    Process {
        id: commandExecutionProc
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
            requester.makeRequest(); // Continue
        }
    }

    function handleFunctionCall(name, args: var, message: AiMessageData) {
        if (name === "switch_to_search_mode") {
            const modelId = root.currentModelId;
            root.currentTool = "search"
            root.postResponseHook = () => { root.currentTool = "functions" }
            addFunctionOutputMessage(name, Translation.tr("Switched to search mode. Continue with the user's request."))
            requester.makeRequest();
        } else if (name === "get_shell_config") {
            const configJson = CF.ObjectUtils.toPlainObject(Config.options)
            addFunctionOutputMessage(name, JSON.stringify(configJson));
            requester.makeRequest();
        } else if (name === "set_shell_config") {
            if (!args.key || !args.value) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `key` and `value`."));
                return;
            }
            const key = args.key;
            const value = args.value;
            Config.setNestedValue(key, value);
        } else if (name === "run_shell_command") {
            if (!args.command || args.command.length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `command`."));
                return;
            }
            const contentToAppend = `\n\n**Command execution request**\n\n\`\`\`command\n${args.command}\n\`\`\``;
            message.rawContent += contentToAppend;
            message.content += contentToAppend;
            message.functionPending = true; // Use thinking to indicate the command is waiting for approval
        } else if (name === "set_owner_name") {
            if (!args.name || args.name.trim().length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `name`."));
                requester.makeRequest();
                return;
            }
            root.setOwnerName(args.name.trim());
            addFunctionOutputMessage(name, Translation.tr("Saved. The owner is now known as %1.").arg(root.ownerName));
            requester.makeRequest();
        } else if (name === "remember") {
            if (!args.text || args.text.trim().length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `text`."));
                requester.makeRequest();
                return;
            }
            MemoryService.remember(args.text.trim(), args.type ?? "fact", [], "model", resp => {
                if (resp && resp.ok) {
                    addFunctionOutputMessage(name, resp.stored
                        ? Translation.tr("Remembered.")
                        : Translation.tr("Already in memory."));
                } else {
                    addFunctionOutputMessage(name, Translation.tr("Memory is unavailable right now."));
                }
                requester.makeRequest();
            });
        } else if (name === "recall") {
            if (!args.query || args.query.trim().length === 0) {
                addFunctionOutputMessage(name, Translation.tr("Invalid arguments. Must provide `query`."));
                requester.makeRequest();
                return;
            }
            MemoryService.recall(args.query.trim(), undefined, results => {
                if (results && results.length > 0) {
                    addFunctionOutputMessage(name, results.map(r => `- ${r.text}`).join("\n"));
                } else {
                    addFunctionOutputMessage(name, Translation.tr("No relevant memories found."));
                }
                requester.makeRequest();
            });
        }
        else root.addMessage(Translation.tr("Unknown function call: %1").arg(name), "assistant");
    }

    function setOwnerName(name) {
        Persistent.states.ai.ownerName = name.trim();
    }

    FileView {
        id: compactorScriptFile
        path: ""
        blockLoading: true
        watchChanges: false
    }

    Process {
        id: compactor
        command: ["bash", "/tmp/quickshell/ai/compact.sh"]
        property var _msg: null
        stdinEnabled: false

        stdout: SplitParser {
            onRead: data => {
                if (!compactor._msg || data.length === 0) return;
                try {
                    root.currentApiStrategy.parseResponseLine(data, compactor._msg);
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

    FileView {
        id: chatSaveFile
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
        getSavedChats.running = true;
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
            // console.log(saveContent)
            const saveData = JSON.parse(saveContent)
            root.clearMessages(false)
            root.messageIDs = saveData.map((_, i) => {
                return i
            })
            // console.log(JSON.stringify(messageIDs))
            for (let i = 0; i < saveData.length; i++) {
                const message = saveData[i];
                root.messageByID[i] = root.aiMessageComponent.createObject(root, {
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
            getSavedChats.running = true;
        }
    }

    Timer {
        id: cooldownTimer
        interval: 20000
        repeat: false
        onTriggered: { root._cooldownActive = false; root._errorStreak = 0; }
    }

    // Returns "continue" | "complete" | "compact_then_continue" (#8)
    function classify_step() {
        if (root.messageIDs.length === 0) return "complete";
        const lastId = root.messageIDs[root.messageIDs.length - 1];
        const lastMsg = root.messageByID[lastId];
        if (!lastMsg || lastMsg.role !== "assistant") return "continue";
        if (root.tokenCount.total > 0 && root.tokenCount.total > root.compactionThreshold * 0.85) {
            return "compact_then_continue";
        }
        const text = (lastMsg.rawContent ?? "").toUpperCase();
        if (lastMsg.functionCall && !lastMsg.done) return "continue";
        if (text.includes("DONE") || text.includes("TASK COMPLETE") || text.includes("RESEARCH_COMPLETE")) return "complete";
        return "complete";
    }

    // Inject a hidden context pair into message history (#11)
    function injectContext(text) {
        const ctxU = root.aiMessageComponent.createObject(root, {
            "role": "user", "content": text, "rawContent": text,
            "thinking": false, "done": true, "visibleToUser": false
        });
        const uid = root.idForMessage(ctxU);
        root.messageIDs = [...root.messageIDs, uid];
        root.messageByID[uid] = ctxU;
        const ctxA = root.aiMessageComponent.createObject(root, {
            "role": "assistant", "content": "Understood, I have that context.",
            "rawContent": "Understood, I have that context.",
            "thinking": false, "done": true, "visibleToUser": false
        });
        const aid = root.idForMessage(ctxA);
        root.messageIDs = [...root.messageIDs, aid];
        root.messageByID[aid] = ctxA;
    }

    // Run a subtask in an isolated context; result injected back into main chat (#15)
    function spawnSubtask(description) {
        if (root._savedContext) {
            root.addMessage(Translation.tr("A subtask is already running."), root.interfaceRole);
            return;
        }
        root._savedContext = {
            "messageIDs": root.messageIDs.slice(),
            "messageByID": Object.assign({}, root.messageByID),
            "tokenInput": root.tokenCount.input,
            "tokenOutput": root.tokenCount.output,
            "tokenTotal": root.tokenCount.total
        };
        root.messageIDs = [];
        root.messageByID = ({});
        root.tokenCount.input = -1;
        root.tokenCount.output = -1;
        root.tokenCount.total = -1;
        root.addMessage(Translation.tr("_Subtask: %1_").arg(description), root.interfaceRole);
        root.postResponseHook = () => {
            const lastId = root.messageIDs[root.messageIDs.length - 1];
            const lastMsg = root.messageByID[lastId];
            const resultText = (lastMsg && lastMsg.role === "assistant")
                ? lastMsg.rawContent
                : Translation.tr("(no result)");
            if (root._savedContext) {
                root.messageIDs = root._savedContext.messageIDs;
                root.messageByID = root._savedContext.messageByID;
                root.tokenCount.input = root._savedContext.tokenInput;
                root.tokenCount.output = root._savedContext.tokenOutput;
                root.tokenCount.total = root._savedContext.tokenTotal;
                root._savedContext = null;
            }
            root.addMessage(Translation.tr("**Subtask result:**\n\n%1").arg(resultText), root.interfaceRole);
        };
        root.sendUserMessage(description);
    }
}
