pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell
import QtQuick

/**
 * Deep research loop: Think → Search/Recall → Synthesize.
 * Driven by the existing Ai service. Each iteration spends at most `toolBudget`
 * tool calls; every source the tools returned is collected as it goes, and the
 * final synthesis is handed the numbered list so it can cite it. The list stays
 * in `sources` after the run for the UI to render.
 *
 * Usage: ResearchService.start("your query")
 */
Singleton {
    id: root

    property bool active: false
    property string query: ""
    property int iteration: 0
    readonly property int maxIterations: Config.options?.ai?.research?.maxIterations ?? 5
    readonly property int toolBudget: Config.options?.ai?.research?.toolBudget ?? 3

    // [{ url, title, tool, iteration }] — deduplicated by url, in the order found.
    property var sources: []
    property int toolCalls: 0

    property int _scanned: 0
    property var _priorTool: null
    property bool _overspent: false
    property int _iterationSpend: 0

    readonly property var sourceTools: ["search_web", "fetch_url", "recall"]

    function start(q) {
        if (root.active) {
            Ai.addMessage(Translation.tr("Research already in progress. Wait for it to finish."), Ai.interfaceRole);
            return;
        }
        root.query = q;
        root.iteration = 0;
        root.sources = [];
        root.toolCalls = 0;
        root._scanned = Ai.messageIDs.length;
        root._priorTool = null;
        root.active = true;
        Ai.addMessage(Translation.tr("_Starting research: %1_").arg(q), Ai.interfaceRole);
        root._runIteration();
    }

    function _runIteration() {
        if (!root.active) return;
        root.iteration++;
        root._iterationSpend = 0;
        if (root.iteration > root.maxIterations) {
            root._finish();
            return;
        }
        Ai.addMessage(Translation.tr("_Research iteration %1/%2…_").arg(root.iteration).arg(root.maxIterations), Ai.interfaceRole);

        const budget = Translation.tr("You may call at most %1 tools this iteration. "
            + "For every source you use, quote its URL in your reply.").arg(root.toolBudget)
            + (root._overspent ? " " + Translation.tr("You went over that budget last iteration; use fewer tools.") : "");
        const prompt = root.iteration === 1
            ? "[RESEARCH MODE] Research query: \"" + root.query + "\"\n\n"
                + "Phase: Think and Search. Use available tools to gather information. " + budget + " "
                + "When you have gathered enough to give a comprehensive answer, write RESEARCH_COMPLETE on its own line "
                + "followed by a well-structured synthesis of your findings."
            : "[RESEARCH MODE] Continue researching \"" + root.query + "\". Iteration " + root.iteration + "/" + root.maxIterations + ". "
                + "Build on what you've already found. " + budget + " "
                + root._knownSourcesBlock()
                + "If you now have enough for a comprehensive answer, "
                + "write RESEARCH_COMPLETE on its own line followed by the synthesis.";

        Ai.postResponseHook = () => root._checkResult();
        Ai.sendUserMessage(prompt);
    }

    /**
     * A tool call is not the end of a turn: the model answers, the tool runs,
     * and only the reply after that is the iteration's result. Advancing on the
     * first response queued the next iteration before a single search had run.
     */
    function _checkResult(force = false) {
        if (!root.active) return;
        const spent = root._collectSources();
        const lastId = Ai.messageIDs[Ai.messageIDs.length - 1];
        const lastMsg = Ai.messageByID[lastId];
        if (!lastMsg) { root._cancel(); return; }

        const midTurn = !force && ((lastMsg.functionName ?? "").length > 0
            || (lastMsg.rawContent ?? "").trim().length === 0);
        if (midTurn) {
            Ai.postResponseHook = () => root._checkResult();
            return;
        }

        root._overspent = spent > root.toolBudget;
        if ((lastMsg.rawContent ?? "").includes("RESEARCH_COMPLETE")) {
            root._complete();
        } else if (root.toolCalls >= root.maxIterations * root.toolBudget || root.iteration >= root.maxIterations) {
            root._finish();
        } else {
            root._runIteration();
        }
    }

    // The response hook is one slot the whole engine shares, and a tool turn can
    // finish without it firing. This harvests sources as they land and restarts
    // a loop that has gone quiet, so a dropped hook costs time, not the results.
    readonly property Timer pulse: Timer {
        interval: 2000
        repeat: true
        running: root.active
        property int idleTicks: 0
        onTriggered: {
            root._collectSources();
            if (Ai.requestActive || Ai.compacting) { pulse.idleTicks = 0; return; }
            pulse.idleTicks++;
            if (pulse.idleTicks < 6) return;
            pulse.idleTicks = 0;
            console.log("[Research] no response for 12s, moving the loop on");
            root._checkResult(true);
        }
    }

    /**
     * Every source the tools have returned. Sources are the point of the loop,
     * so they are pulled out of the messages while they are still in the chat
     * rather than left to be compacted away. A message's id is appended before
     * its content streams in, so this rescans everything and deduplicates by
     * url instead of trusting a high-water mark.
     * @returns how many tool calls this iteration spent
     */
    function _collectSources() {
        const found = root.sources.slice();
        const seen = ({});
        found.forEach(s => { seen[s.url] = true; });
        let spent = 0;

        for (let i = 0; i < Ai.messageIDs.length; i++) {
            const message = Ai.messageByID[Ai.messageIDs[i]];
            if (!message) continue;

            const tool = message.functionName ?? "";
            if (tool.length > 0) {
                if (i >= root._scanned) spent++;
                if (root.sourceTools.indexOf(tool) >= 0) {
                    const body = (message.functionResponse ?? "") + "\n" + (message.rawContent ?? "");
                    root._sourcesIn(body).forEach(source => {
                        if (seen[source.url]) return;
                        seen[source.url] = true;
                        found.push({ "url": source.url, "title": source.title,
                            "tool": tool, "iteration": root.iteration });
                    });
                }
            }

            const annotations = message.annotationSources ?? [];
            for (let a = 0; a < annotations.length; a++) {
                const entry = annotations[a];
                const url = (typeof entry === "string") ? entry : (entry.url ?? entry.uri ?? "");
                if (url.length === 0 || seen[url]) continue;
                seen[url] = true;
                found.push({
                    "url": url,
                    "title": (typeof entry === "string") ? "" : (entry.title ?? ""),
                    "tool": "grounding",
                    "iteration": root.iteration,
                });
            }
        }

        root._scanned = Ai.messageIDs.length;
        root.sources = found;
        root.toolCalls += spent;
        root._iterationSpend += spent;
        return root._iterationSpend;
    }

    // Search results arrive as "1. Title\n   https://…", so the line above a
    // bare url is its title.
    function _sourcesIn(text) {
        const out = [];
        const lines = (text ?? "").split("\n");
        let label = "";
        for (let i = 0; i < lines.length; i++) {
            const match = lines[i].match(/https?:\/\/[^\s"'<>)\]]+/);
            if (match) {
                out.push({ "url": match[0].replace(/[.,;:]+$/, ""), "title": label });
                label = "";
                continue;
            }
            const line = lines[i].replace(/^\s*\d+[.)]\s*/, "").trim();
            label = (line.length > 0 && line.length <= 120) ? line : "";
        }
        return out;
    }

    function _knownSourcesBlock() {
        if (root.sources.length === 0) return "";
        return "Sources already retrieved:\n"
            + root.sources.map((s, i) => `[${i + 1}] ${s.url}`).join("\n") + "\n\n";
    }

    function sourcesMarkdown() {
        if (root.sources.length === 0) return "";
        return root.sources.map((s, i) =>
            `[${i + 1}] ${s.title.length > 0 ? s.title + " — " : ""}${s.url}`).join("\n");
    }

    function _complete() {
        root.active = false;
        root._restoreTools();
        Ai.addMessage(Translation.tr("_Research complete (%1 iteration(s), %2 tool call(s), %3 source(s))._")
            .arg(root.iteration).arg(root.toolCalls).arg(root.sources.length), Ai.interfaceRole);
        if (root.sources.length > 0) {
            Ai.addMessage(Translation.tr("**Sources**\n\n%1").arg(root.sourcesMarkdown()), Ai.interfaceRole);
        }
    }

    /** The synthesis turn gets the sources and no tools, so it has to write the answer. */
    function _finish() {
        Ai.addMessage(Translation.tr("_Synthesising from %1 source(s)…_").arg(root.sources.length), Ai.interfaceRole);
        if (root._priorTool === null) {
            root._priorTool = Ai.currentTool;
            Ai.setTool("none");
        }
        Ai.postResponseHook = () => {
            root._collectSources();
            root._complete();
        };
        Ai.sendUserMessage(
            "[RESEARCH MODE] Tool budget spent. Provide your final synthesis for: \"" + root.query + "\"\n\n"
            + (root.sources.length > 0
                ? "Cite these sources by number where you use them:\n" + root.sourcesMarkdown() + "\n\n"
                : "")
            + "End with a Sources section listing every source you cited."
        );
    }

    function _restoreTools() {
        if (root._priorTool === null) return;
        Ai.setTool(root._priorTool);
        root._priorTool = null;
    }

    function _cancel() {
        root.active = false;
        root._restoreTools();
        root.query = "";
    }
}
