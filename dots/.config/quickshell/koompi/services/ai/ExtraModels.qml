pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import QtQuick

/**
 * `ai.extraModels` from config.json: each entry becomes an AiModel in the
 * registry under its `model` id, so `/model <id>` and the picker see it. Loaded
 * again when the config or `policies.ai` changes; entries that vanished are
 * dropped. The schema is in docs/agents/ai.md.
 */
QtObject {
    id: root

    property QtObject registry
    property var _added: []
    property var _warned: ({}) // index -> the entry text already warned about

    function isLocalEndpoint(endpoint: string): bool {
        return endpoint.includes("localhost") || endpoint.includes("127.0.0.1");
    }

    function load() {
        const entries = Config.options?.ai?.extraModels ?? [];
        const localOnly = Config.options?.policies?.ai === 2;
        const models = Object.assign({}, root.registry.models);
        for (const id of root._added) {
            if (models[id]) models[id].destroy();
            delete models[id];
        }
        // The registry's own binding on policies.ai dies with the first assignment
        // below, so the remote slot is applied here from then on.
        if (localOnly) delete models.remote;
        else if (!("remote" in models)) models.remote = root.registry.remoteModelObj;

        const added = [];
        for (let i = 0; i < entries.length; i++) {
            const entry = entries[i] ?? {};
            const id = `${entry.model ?? ""}`.trim();
            const endpoint = `${entry.endpoint ?? ""}`.trim();
            if (id.length === 0 || endpoint.length === 0 || id === "remote" || id === "local") {
                // the config reloads after every write-back; one warning per broken entry
                const text = JSON.stringify(entry);
                if (root._warned[i] !== text) console.warn(`[AI] ai.extraModels[${i}] skipped: an entry needs a "model" id (not remote/local) and an "endpoint"`);
                root._warned[i] = text;
                continue;
            }
            if (localOnly && !root.isLocalEndpoint(endpoint)) continue;
            const window = Math.floor(Number(entry.context_window ?? 0));
            models[id] = root.registry.aiModelComponent.createObject(root.registry, {
                "model": id,
                "name": `${entry.name ?? ""}`.length > 0 ? `${entry.name}` : root.registry.guessModelName(id),
                "endpoint": endpoint,
                "api_format": `${entry.api_format ?? "openai"}`,
                "key_id": `${entry.key_id ?? root.registry.inferKeyIdForModel(id)}`,
                "requires_key": entry.requires_key === undefined ? !root.isLocalEndpoint(endpoint) : entry.requires_key === true,
                "key_get_link": `${entry.key_get_link ?? ""}`,
                "key_get_description": `${entry.key_get_description ?? ""}`,
                "icon": `${entry.icon ?? root.registry.guessModelLogo(id)}`,
                "description": `${entry.description ?? Translation.tr("Custom | %1").arg(id)}`,
                "homepage": `${entry.homepage ?? ""}`,
                "contextWindow": window > 0 ? window : 0,
            });
            added.push(id);
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
