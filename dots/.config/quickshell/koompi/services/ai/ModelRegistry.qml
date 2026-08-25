pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

/**
 * Which brains are available and which one is answering: the model slots, the
 * endpoint/format/key inference behind them, the discovery of locally installed
 * models, and the API-format strategies. `engine` is the Ai facade.
 */
QtObject {
    id: root

    property QtObject engine

    readonly property var apiKeys: KeyringStorage.keyringData?.apiKeys ?? {}
    readonly property var apiKeysLoaded: KeyringStorage.loaded
    readonly property bool currentModelHasApiKey: {
        const model = root.models[root.currentModelId];
        if (!model || !model.requires_key) return true;
        if (!root.apiKeysLoaded) return false;
        const key = root.apiKeys[model.key_id];
        return (key?.length > 0);
    }

    property Component aiModelComponent: AiModel {}
    readonly property ExtraModels extraModels: ExtraModels { registry: root }
    property Component geminiApiStrategy: GeminiApiStrategy {}
    property Component openaiApiStrategy: OpenAiApiStrategy {}
    property Component mistralApiStrategy: MistralApiStrategy {}

    function safeModelName(modelName) {
        return modelName.replace(/:/g, "_").replace(/ /g, "-").replace(/\//g, "-")
    }

    // Provider rules by model name, first match wins: [match, endpoint, api
    // format, key id, key link]. stealth/ is 0xAlpha served by tokenra; any other
    // name with a "/" is an OpenRouter route. %1 in an endpoint is the model name.
    readonly property var providers: [
        [/^stealth\//, "https://tokenra.io/v1/chat/completions", "openai", "oxalpha", "https://oxalpha.io/ox-alpha-api.html"],
        [/\//, "https://openrouter.ai/api/v1/chat/completions", "openai", "openrouter", ""],
        [/^(gemini|gemma)/, "https://generativelanguage.googleapis.com/v1beta/models/%1:streamGenerateContent", "gemini", "gemini", ""],
        [/^(mistral|codestral|devstral)/, "https://api.mistral.ai/v1/chat/completions", "mistral", "mistral", ""],
        [/^(gpt|o1|o3|o4)/, "https://api.openai.com/v1/chat/completions", "openai", "openai", ""],
        [/^deepseek/, "https://api.deepseek.com/chat/completions", "openai", "deepseek", ""],
        [/^(kimi|moonshot)/, "https://api.moonshot.ai/v1/chat/completions", "openai", "moonshot", ""],
        [/^glm/, "https://api.z.ai/api/paas/v4/chat/completions", "openai", "zai", ""],
        [/^minimax/, "https://api.minimax.io/v1/chat/completions", "openai", "minimax", ""],
        [/./, "https://api.openai.com/v1/chat/completions", "openai", "custom", ""],
    ]

    function inferProvider(modelName) {
        const m = modelName.toLowerCase();
        const p = root.providers.find(rule => rule[0].test(m)) ?? root.providers[root.providers.length - 1];
        return { endpoint: p[1].replace("%1", modelName), api_format: p[2], key_id: p[3], key_get_link: p[4] };
    }
    function inferEndpointForModel(modelName) { return root.inferProvider(modelName).endpoint; }
    function inferApiFormatForModel(modelName) { return root.inferProvider(modelName).api_format; }
    function inferKeyIdForModel(modelName) { return root.inferProvider(modelName).key_id; }

    readonly property AiModel remoteModelObj: AiModel {
        model: Persistent.states?.ai?.remoteModel ?? "stealth/ox-alpha"
        name: model
        icon: root.guessModelLogo(model)
        description: Translation.tr("Remote | %1").arg(model)
        endpoint: {
            const stored = Persistent.states?.ai?.remoteEndpoint ?? "";
            return stored.length > 0 ? stored : root.inferEndpointForModel(model);
        }
        requires_key: !endpoint.includes("localhost") && !endpoint.includes("127.0.0.1")
        key_id: root.inferKeyIdForModel(model)
        key_get_link: root.inferProvider(model).key_get_link
        api_format: {
            const stored = Persistent.states?.ai?.remoteFormat ?? "";
            return stored.length > 0 ? stored : root.inferApiFormatForModel(model);
        }
    }

    readonly property AiModel localModelObj: AiModel {
        model: Persistent.states?.ai?.localModel ?? ""
        name: model.length > 0 ? root.guessModelName(model) : Translation.tr("Local (not set)")
        icon: root.guessModelLogo(model)
        description: Translation.tr("Local | %1 | %2").arg(endpoint).arg(model.length > 0 ? model : "?")
        endpoint: Persistent.states?.ai?.localEndpoint ?? "http://localhost:11434/v1/chat/completions"
        requires_key: false
        api_format: "openai"
    }

    property var models: Config.options.policies.ai === 2
        ? { "local": root.localModelObj }
        : { "remote": root.remoteModelObj, "local": root.localModelObj }
    property var modelList: Object.keys(root.models)
    property var currentModelId: {
        const stored = Persistent.states?.ai?.model ?? "";
        if (stored in root.models) return stored;
        return "remote" in root.models ? "remote" : "local";
    }

    property var apiStrategies: {
        "openai": root.openaiApiStrategy.createObject(root),
        "gemini": root.geminiApiStrategy.createObject(root),
        "mistral": root.mistralApiStrategy.createObject(root),
    }
    property ApiStrategy currentApiStrategy: root.apiStrategies[root.models[root.currentModelId]?.api_format || "openai"]

    Component.onCompleted: {
        // Migrate: old state may have a model ID like "gemini-2.5-flash" that no
        // longer exists as a key in models{}. Treat it as a remote model name.
        const stored = Persistent.states?.ai?.model ?? "";
        if (stored !== "remote" && stored !== "local" && stored.length > 0) {
            if (root.modelList.indexOf(stored) === -1) {
                Persistent.states.ai.remoteModel = stored;
                Persistent.states.ai.model = "remote";
            }
        }
        root.setModel(root.currentModelId, false, false);
    }

    function guessModelLogo(model) {
        const m = model.toLowerCase();
        if (m.startsWith("stealth/")) return "oxalpha-symbolic";
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
        if (model.toLowerCase().startsWith("stealth/")) return "0xAlpha";
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
            [modelName]: root.aiModelComponent.createObject(root, data)
        });
        root.modelList = Object.keys(root.models); // the binding to models is long broken
    }

    readonly property Process getOllamaModels: Process {
        running: true
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-ollama-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    // raw names here would survive into modelList alongside the safe
                    // ones addModel derives, and setModel matches against both
                    dataJson.forEach(model => {
                        const safeModelName = root.safeModelName(model);
                        root.addModel(safeModelName, {
                            "name": root.guessModelName(model),
                            "icon": root.guessModelLogo(model),
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

    // not at startup: the server is socket-activated, so the list is discovered
    // when the sidebar opens and wakes it
    function refreshLitertLmModels() {
        root.getLitertLmModels.running = true;
    }

    readonly property Process getLitertLmModels: Process {
        running: false
        command: ["bash", "-c", `${Directories.scriptPath}/ai/show-installed-litert-lm-models.sh`.replace(/file:\/\//, "")]
        stdout: SplitParser {
            onRead: data => {
                try {
                    if (data.length === 0) return;
                    const dataJson = JSON.parse(data);
                    dataJson.forEach(model => {
                        root.addModel(root.safeModelName(model), {
                            "name": root.guessModelName(model),
                            "icon": root.guessModelLogo(model),
                            "description": Translation.tr("LiteRT-LM | %1").arg(model),
                            "endpoint": "http://127.0.0.1:9379/v1/chat/completions",
                            "model": model,
                            "requires_key": false,
                            // measured on gemma4-e4b at temperature 0: clean at 1461 B
                            // of compact tool JSON, digits start dropping at 1965 B
                            "toolBlockByteLimit": 1461,
                        })
                    });
                    root.modelList = Object.keys(root.models);
                    root.warmLitertLm();
                } catch (e) {
                    console.log("Could not fetch LiteRT-LM models:", e);
                }
            }
        }
    }

    // engine init is ~7s and runs on the first completion, not on /v1/models, so
    // spend it while the user is still typing. Runs after discovery because the
    // model has to be known: warming the wrong one forces a re-init.
    function warmLitertLm() {
        const model = root.getModel();
        if (!model || (model.endpoint ?? "").indexOf("127.0.0.1:9379") < 0) return;
        if (root.warmLitertLmProc.running || root.engine.requestActive) return;
        root.warmLitertLmProc.command = [
            "curl", "-sf", "-o", "/dev/null", "-m", "120", "-X", "POST", model.endpoint,
            "-H", "Content-Type: application/json",
            "-d", JSON.stringify({
                "model": model.model,
                "messages": [{"role": "user", "content": "hi"}],
                "stream": false,
                "max_tokens": 1,
            }),
        ];
        root.warmLitertLmProc.running = true;
    }

    readonly property Process warmLitertLmProc: Process {
        running: false
    }

    function addApiKeyAdvice(model) {
        root.engine.addMessage(
            Translation.tr('To set an API key, pass it with the %4 command\n\nTo view the key, pass "get" with the command<br/>\n\n### For %1:\n\n**Link**: %2\n\n%3')
                .arg(model.name).arg(model.key_get_link).arg(model.key_get_description ?? Translation.tr("<i>No further instruction provided</i>")).arg("/key"),
            root.engine.interfaceRole
        );
    }

    function getModel() {
        return root.models[root.currentModelId];
    }

    function setModel(modelId, feedback = true, setPersistentState = true) {
        modelId = (modelId ?? "").trim().toLowerCase()

        // "/model" with nothing after it asks which model answers; it must not
        // fall through to the remote branch, which would store "" as the name
        // and drop the stored endpoint
        if (modelId.length === 0) {
            if (feedback) root.engine.addMessage(
                Translation.tr("Current model: **%1**\n\n%2\n\nChange with `/model remote NAME`, `/model local:NAME` or `/model local`")
                    .arg(root.getModel().name).arg(root.getModel().description),
                root.engine.interfaceRole
            );
            return;
        }

        // "local:<name>" - set local model name and switch to local slot
        if (modelId.startsWith("local:")) {
            const localName = modelId.slice(6).trim();
            if (setPersistentState) {
                Persistent.states.ai.localModel = localName;
                Persistent.states.ai.model = "local";
            }
            if (feedback) root.engine.addMessage(
                Translation.tr("Local model set to **%1**\n\nEndpoint: %2").arg(localName).arg(root.localModelObj.endpoint),
                root.engine.interfaceRole
            );
            return;
        }

        // "local" - switch to local slot
        if (modelId === "local") {
            if (setPersistentState) Persistent.states.ai.model = "local";
            if (feedback) root.engine.addMessage(
                root.localModelObj.model.length > 0
                    ? Translation.tr("Switched to local model: **%1**").arg(root.localModelObj.model)
                    : Translation.tr("Switched to local slot. Set model with `/model local:NAME`"),
                root.engine.interfaceRole
            );
            return;
        }

        // Ollama auto-discovered models (any key other than "remote"/"local")
        if (modelId !== "remote" && root.modelList.indexOf(modelId) !== -1) {
            const model = root.models[modelId];
            if (Config.options.policies.ai === 2 && !model.endpoint.includes("localhost")) {
                root.engine.addMessage(
                    Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                    root.engine.interfaceRole
                );
                return;
            }
            if (setPersistentState) Persistent.states.ai.model = modelId;
            if (feedback) root.engine.addMessage(Translation.tr("Model set to %1").arg(model.name), root.engine.interfaceRole);
            return;
        }

        // "remote" or any unrecognised name - treat as remote model name
        if (Config.options.policies.ai === 2) {
            root.engine.addMessage(
                Translation.tr("Online models disallowed\n\nControlled by `policies.ai` config option"),
                root.engine.interfaceRole
            );
            return;
        }

        const newRemoteModel = (modelId === "remote")
            ? (Persistent.states?.ai?.remoteModel ?? "stealth/ox-alpha")
            : modelId;
        if (setPersistentState) {
            Persistent.states.ai.remoteModel = newRemoteModel;
            Persistent.states.ai.model = "remote";
            if (modelId !== "remote") {
                Persistent.states.ai.remoteEndpoint = "";
                Persistent.states.ai.remoteFormat = "";
            }
        }
        if (feedback) root.engine.addMessage(Translation.tr("Remote model set to **%1**").arg(newRemoteModel), root.engine.interfaceRole);
        if (root.remoteModelObj.requires_key) {
            if (root.apiKeysLoaded && (!root.apiKeys[root.remoteModelObj.key_id] || root.apiKeys[root.remoteModelObj.key_id].length === 0)) {
                root.addApiKeyAdvice(root.remoteModelObj);
            }
        }
    }

    function setEndpoint(url) {
        if (!url || url.trim().length === 0) {
            root.engine.addMessage(
                Translation.tr("Remote endpoint: **%1**\n\nLocal endpoint: **%2**\n\nChange with `/endpoint remote URL` or `/endpoint local URL`")
                    .arg(root.remoteModelObj.endpoint).arg(root.localModelObj.endpoint),
                root.engine.interfaceRole
            );
            return;
        }
        url = url.trim();
        if (url.startsWith("remote ")) {
            Persistent.states.ai.remoteEndpoint = url.slice(7).trim();
            root.engine.addMessage(Translation.tr("Remote endpoint set to **%1**").arg(Persistent.states.ai.remoteEndpoint), root.engine.interfaceRole);
        } else if (url.startsWith("local ")) {
            Persistent.states.ai.localEndpoint = url.slice(6).trim();
            root.engine.addMessage(Translation.tr("Local endpoint set to **%1**").arg(Persistent.states.ai.localEndpoint), root.engine.interfaceRole);
        } else if (url === "reset") {
            Persistent.states.ai.remoteEndpoint = "";
            root.engine.addMessage(Translation.tr("Remote endpoint reset to auto-infer"), root.engine.interfaceRole);
        } else {
            Persistent.states.ai.remoteEndpoint = url;
            root.engine.addMessage(Translation.tr("Remote endpoint set to **%1**").arg(url), root.engine.interfaceRole);
        }
    }

    function setApiKey(key) {
        const model = root.models[root.currentModelId];
        if (!model.requires_key) {
            root.engine.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), root.engine.interfaceRole);
            return;
        }
        if (!key || key.length === 0) {
            root.addApiKeyAdvice(model)
            return;
        }
        KeyringStorage.setNestedField(["apiKeys", model.key_id], key.trim());
        root.engine.addMessage(Translation.tr("API key set for %1").arg(model.name), root.engine.interfaceRole);
    }

    function printApiKey() {
        const model = root.models[root.currentModelId];
        if (model.requires_key) {
            const key = root.apiKeys[model.key_id];
            if (key) {
                const masked = key.length > 8 ? `${key.slice(0, 4)}…${key.slice(-4)}` : "••••";
                root.engine.addMessage(Translation.tr("API key: `%1` (masked)").arg(masked), root.engine.interfaceRole);
            } else {
                root.engine.addMessage(Translation.tr("No API key set for %1").arg(model.name), root.engine.interfaceRole);
            }
        } else {
            root.engine.addMessage(Translation.tr("%1 does not require an API key").arg(model.name), root.engine.interfaceRole);
        }
    }
}
