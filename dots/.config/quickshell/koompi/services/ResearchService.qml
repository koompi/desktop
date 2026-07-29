pragma Singleton
pragma ComponentBehavior: Bound

import qs.modules.common
import qs.services
import Quickshell
import QtQuick

/**
 * Deep research loop: Think → Search/Recall → Synthesize.
 * Driven by the existing Ai service. Each iteration sends a research-mode
 * message; the loop continues until the LLM emits "RESEARCH_COMPLETE" or
 * maxIterations is reached.
 *
 * Usage: ResearchService.start("your query")
 */
Singleton {
    id: root

    property bool active: false
    property string query: ""
    property int iteration: 0
    readonly property int maxIterations: 5

    function start(q) {
        if (root.active) {
            Ai.addMessage(Translation.tr("Research already in progress. Wait for it to finish."), Ai.interfaceRole);
            return;
        }
        root.query = q;
        root.iteration = 0;
        root.active = true;
        Ai.addMessage(Translation.tr("_Starting research: %1_").arg(q), Ai.interfaceRole);
        root._runIteration();
    }

    function _runIteration() {
        if (!root.active) return;
        root.iteration++;
        if (root.iteration > root.maxIterations) {
            root._finish();
            return;
        }
        Ai.addMessage(Translation.tr("_Research iteration %1/%2…_").arg(root.iteration).arg(root.maxIterations), Ai.interfaceRole);

        const prompt = root.iteration === 1
            ? "[RESEARCH MODE] Research query: \"" + root.query + "\"\n\n"
                + "Phase: Think and Search. Use available tools to gather information. "
                + "When you have gathered enough to give a comprehensive answer, write RESEARCH_COMPLETE on its own line "
                + "followed by a well-structured synthesis of your findings."
            : "[RESEARCH MODE] Continue researching \"" + root.query + "\". Iteration " + root.iteration + "/" + root.maxIterations + ". "
                + "Build on what you've already found. If you now have enough for a comprehensive answer, "
                + "write RESEARCH_COMPLETE on its own line followed by the synthesis.";

        Ai.postResponseHook = () => root._checkResult();
        Ai.sendUserMessage(prompt);
    }

    function _checkResult() {
        if (!root.active) return;
        const lastId = Ai.messageIDs[Ai.messageIDs.length - 1];
        const lastMsg = Ai.messageByID[lastId];
        if (!lastMsg) { root._cancel(); return; }
        if ((lastMsg.rawContent ?? "").includes("RESEARCH_COMPLETE")) {
            root.active = false;
            Ai.addMessage(Translation.tr("_Research complete (%1 iteration(s))._").arg(root.iteration), Ai.interfaceRole);
        } else if (root.iteration < root.maxIterations) {
            root._runIteration();
        } else {
            root._finish();
        }
    }

    function _finish() {
        root.active = false;
        Ai.addMessage(Translation.tr("_Max iterations reached. Requesting final synthesis…_"), Ai.interfaceRole);
        Ai.postResponseHook = () => { root.active = false; };
        Ai.sendUserMessage(
            "[RESEARCH MODE] Max iterations reached. Provide your best final synthesis for: \"" + root.query + "\""
        );
    }

    function _cancel() {
        root.active = false;
        root.query = "";
    }
}
