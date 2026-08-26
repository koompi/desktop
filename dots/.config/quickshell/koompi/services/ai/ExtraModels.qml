pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick
import "endpoints.js" as Endpoints

/**
 * `ai.extraModels` from config.json: each entry becomes an AiModel in the
 * registry under its lower-cased `model` id, so `/model <id>` and the picker see
 * it. Loaded again when the config or `policies.ai` changes; entries that
 * vanished are dropped. The schema is in docs/agents/ai.md.
 */
QtObject {
    id: root

    property QtObject registry
    property var _added: ({}) // id -> the AiModel this loader created for it
    property var _warned: ({}) // index -> the entry text already warned about

    // the config reloads after every write-back; one warning per broken entry
    function warnOnce(index: int, entry, reason: string) {
        const text = `${reason} ${JSON.stringify(entry)}`;
        if (root._warned[index] !== text) console.warn(`[AI] ai.extraModels[${index}] skipped: ${reason}`);
        root._warned[index] = text;
    }

    function load() {
        const entries = Config.options?.ai?.extraModels ?? [];
        const localOnly = Config.options?.policies?.ai === 2;
        const models = Object.assign({}, root.registry.models);
        // Only what this loader put there is taken back. An id a discovered
        // Ollama/LiteRT model has taken since stays theirs; ours goes either way.
        for (const id in root._added) {
            root._added[id].destroy();
            if (models[id] === root._added[id]) delete models[id];
        }
        // The registry's own binding on policies.ai dies with the first assignment
        // below, so the remote slot is applied here from then on.
        if (localOnly) delete models.remote;
        else if (!("remote" in models)) models.remote = root.registry.remoteModelObj;

        const added = {};
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i] ?? {};
            const id = `${entry.model ?? ""}`.trim().toLowerCase(); // /model lowercases its argument
            const endpoint = `${entry.endpoint ?? ""}`.trim();
            if (id.length === 0 || endpoint.length === 0 || id === "remote" || id === "local") {
                root.warnOnce(i, entry, `an entry needs a "model" id (not remote/local) and an "endpoint"`);
                continue;
            }
            if (id in models) {
                root.warnOnce(i, entry, `the id "${id}" is already taken by another model`);
                continue;
            }
            if (localOnly && !Endpoints.isLocal(endpoint)) continue;
            try {
                const window = Math.floor(Number(entry.context_window ?? 0));
                models[id] = root.registry.aiModelComponent.createObject(root.registry, {
                    "model": id,
                    "name": `${entry.name ?? ""}`.length > 0 ? `${entry.name}` : root.registry.guessModelName(id),
                    "endpoint": endpoint,
                    "api_format": `${entry.api_format ?? "openai"}`,
                    "key_id": `${entry.key_id ?? root.registry.inferKeyIdForModel(id)}`,
                    // absent: a local endpoint needs none; present: only a literal false turns the gate off
                    "requires_key": entry.requires_key === undefined ? !Endpoints.isLocal(endpoint) : entry.requires_key !== false,
                    "key_get_link": `${entry.key_get_link ?? ""}`,
                    "key_get_description": `${entry.key_get_description ?? ""}`,
                    "icon": `${entry.icon ?? root.registry.guessModelLogo(id)}`,
                    "description": `${entry.description ?? Translation.tr("Custom | %1").arg(id)}`,
                    "homepage": `${entry.homepage ?? ""}`,
                    "contextWindow": window > 0 ? window : 0,
                });
                added[id] = models[id];
            } catch (e) {
                delete models[id];
                root.warnOnce(i, entry, `could not be created: ${e}`);
            }
        }
        root._added = added;
        root.registry.models = models;
        root.registry.modelList = Object.keys(models);
    }

    // callLater: the registry's bindings on the same signals run first, so the
    // reload sees the slots as they are after the policy change
    readonly property Connections configWatch: Connections {
        target: Config.options.ai
        function onExtraModelsChanged() { Qt.callLater(root.load); }
    }
    readonly property Connections policyWatch: Connections {
        target: Config.options.policies
        function onAiChanged() { Qt.callLater(root.load); }
    }

    Component.onCompleted: root.load()
}
