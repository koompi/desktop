import qs.services
import qs.modules.common
import qs.modules.common.functions
import QtQuick

// The composer's completion source. Feed it the text with updateSuggestions()
// and read `query` and `entries` back. A command declares the type of its
// argument and the candidate list comes from that type; adding a command with
// arguments adds a case, not another copy of the filter.
QtObject {
    id: root
    property ChatCommands commands: null
    property string query: ""
    property var entries: []

    function argumentCandidates(argType) {
        if (argType === "model") {
            return Ai.modelList.map(modelId => ({
                value: modelId,
                label: Ai.models[modelId]?.name ?? modelId,
                description: Ai.models[modelId]?.description ?? "",
                groupTitle: Translation.tr("Models")
            }));
        }
        if (argType === "prompt") {
            return Ai.promptFiles.map(file => ({
                value: file,
                label: FileUtils.trimFileExt(FileUtils.fileNameForPath(file)),
                description: Translation.tr("Load prompt from %1").arg(file),
                groupTitle: Translation.tr("Prompt files")
            }));
        }
        if (argType === "chat") {
            return Ai.savedChats.map(file => {
                const chatName = FileUtils.trimFileExt(FileUtils.fileNameForPath(file)).trim();
                return {
                    value: chatName,
                    label: chatName,
                    description: Translation.tr("Saved chat %1").arg(chatName),
                    groupTitle: Translation.tr("Saved chats")
                };
            });
        }
        if (argType === "tool") {
            return Ai.availableTools.map(tool => ({
                value: tool,
                label: tool,
                description: Ai.toolDescriptions[tool] ?? "",
                groupTitle: Translation.tr("Tools")
            }));
        }
        return [];
    }

    readonly property var commandEntries: (root.commands?.allCommands ?? []).map(command => ({
        value: `${root.commands.prefix}${command.name}`,
        label: `${root.commands.prefix}${command.name}`,
        description: command.description,
        group: command.group,
        groupTitle: root.commands.groupTitleOf(command.group),
        badge: command.argType.length > 0 ? command.argType : ""
    }))

    function narrow(candidates, query) {
        if (query.length === 0)
            return candidates;
        const results = Fuzzy.go(query, candidates.map(candidate => ({
            name: Fuzzy.prepare(candidate.value),
            candidate: candidate
        })), {
            all: true,
            key: "name"
        });
        return results.map(result => result.obj.candidate);
    }

    // Fuzzy ranking scrambles the order, and a palette whose headings repeat is
    // not grouped. Bucket rather than sort: the engine's sort is not stable, and
    // it reversed each group's ranking.
    function byGroup(entries) {
        const out = [];
        root.commands.commandGroups.forEach(group => {
            entries.forEach(entry => {
                if ((entry.group ?? "") === group.id)
                    out.push(entry);
            });
        });
        entries.forEach(entry => {
            if (out.indexOf(entry) === -1)
                out.push(entry);
        });
        return out;
    }

    function updateSuggestions(text) {
        if (text.length === 0 || !text.startsWith(root.commands.prefix)) {
            root.query = "";
            root.entries = [];
            return;
        }
        const firstSpace = text.indexOf(" ");
        const command = root.commands.allCommands.find(entry => entry.name === (firstSpace === -1 ? text.substring(1) : text.substring(1, firstSpace)));
        if (firstSpace === -1 || !command || command.argType.length === 0 || root.argumentCandidates(command.argType).length === 0) {
            root.query = text;
            root.entries = root.byGroup(root.narrow(root.commandEntries, text.substring(1)));
            return;
        }
        root.query = text.split(" ")[1] ?? "";
        // The first word is the command itself, so a suggestion taken before any
        // argument is typed has to carry the command with it.
        const prefix = text.trim().split(/\s+/).length === 1 ? `${root.commands.prefix}${command.name} ` : "";
        root.entries = root.narrow(root.argumentCandidates(command.argType), root.query).map(candidate => ({
            value: `${prefix}${candidate.value}`,
            label: candidate.label,
            description: candidate.description,
            groupTitle: candidate.groupTitle
        }));
    }
}
