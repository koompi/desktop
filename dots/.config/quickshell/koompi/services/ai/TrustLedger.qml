import qs.services
import "feedbackRules.js" as Rules
import "../../modules/koompi/sidebarLeft/aiChat/grounding.js" as Grounding
import QtQuick

/**
 * Measuring whether any of this is working. Every settled turn is logged with
 * the grounding it claimed; `trustReport` sets that against how often the
 * record shows a turn was corrected, over a window, and only calls the gap
 * once there is enough of a record to call it. The two actions the report
 * offers, recalibrating and pausing recall, live here too. Reads and writes
 * `store`; `engine` is the Ai facade, used to talk to the user.
 */
QtObject {
    id: root

    property QtObject engine
    property FeedbackStore store

    readonly property int maxTurns: 500

    readonly property int windowDays: 7
    readonly property int minTurnsForGap: 10
    readonly property int minCorrectionsForGap: 2

    // What the turn was actually given. `message.sources` currently carries only
    // what the tools of the turn returned; the memories recalled for it are
    // published separately until the producer appends them, and they fed the
    // answer just as much, so the measurement counts both.
    function sourcesOf(turn) {
        return MemoryService.withMemorySources(turn?.sources ?? []);
    }

    function recordTurn(turn) {
        const grounding = Grounding.computeGrounding(root.sourcesOf(turn), turn.assistantText ?? "");
        const entry = {
            "messageId": turn.messageId,
            "sessionId": root.engine?.sessionId ?? "",
            "at": Date.now(),
            "grounding": grounding ? grounding.value : null,
            "sourceCount": root.sourcesOf(turn).length,
            "corrected": false
        };
        const kept = [...root.store.turns, entry];
        root.store.turns = kept.length > root.maxTurns ? kept.slice(kept.length - root.maxTurns) : kept;
        root.store.save();
    }

    readonly property var trustReport: {
        const since = Date.now() - root.windowDays * 86400000;
        const window = root.store.turns.filter(entry => entry.at >= since);
        const grounded = window.filter(entry => entry.grounding !== null && entry.grounding !== undefined);
        const corrections = root.store.corrections.filter(entry => entry.at >= since);
        const correctedGrounded = grounded.filter(entry => entry.corrected).length;

        const stated = grounded.length > 0
            ? grounded.reduce((sum, entry) => sum + entry.grounding, 0) / grounded.length
            : null;
        const measured = grounded.length > 0 ? 1 - correctedGrounded / grounded.length : null;
        const enough = grounded.length >= root.minTurnsForGap && corrections.length >= root.minCorrectionsForGap;

        return {
            "windowDays": root.windowDays,
            "turns": window.length,
            "groundedTurns": grounded.length,
            "corrections": corrections.length,
            "autoRepairs": corrections.filter(entry => String(entry.origin ?? "").indexOf("auto-repair") === 0).length,
            "correctedTurns": correctedGrounded,
            "statedGrounding": stated,
            "measuredAccuracy": measured,
            "gap": (enough && stated !== null && measured !== null) ? stated - measured : null,
            "enough": enough,
            // Only a positive gap is a problem. Claiming less than the record
            // shows is not something to recalibrate away.
            "overconfident": enough && stated !== null && measured !== null && (stated - measured) > 0.1,
            "minTurns": root.minTurnsForGap,
            "minCorrections": root.minCorrectionsForGap,
            "needTurns": Math.max(0, root.minTurnsForGap - grounded.length),
            "needCorrections": Math.max(0, root.minCorrectionsForGap - corrections.length)
        };
    }

    // 36:163-182's two actions, named for what they do here rather than for a
    // proactive surface this shell does not have.
    function recalibrate() {
        root.store.groundingFloor = 0.85;
        root.store.save();
        MemoryService.remember(
            "Always say plainly when an answer is not backed by a source.",
            "instruction",
            ["asserted", `precedence:${Rules.precedence}`, "subject:instruction.backed"],
            Rules.correctionSource,
            (response, error) => {
                const tail = error && error.length > 0 ? Translation.tr(" (memory refused it: %1)").arg(error) : "";
                root.engine.addMessage(
                    Translation.tr("Recalibrated. Below 85% grounding I say I am unsure, and that is now a standing instruction in memory.") + tail,
                    root.engine.interfaceRole);
            });
    }

    function pauseRecall(days) {
        root.store.recallPausedUntil = Date.now() + Math.max(1, days ?? 7) * 86400000;
        root.store.save();
        root.engine.addMessage(
            Translation.tr("Recalled memories are paused for %1 days. Nothing was deleted; I just stop reading them into the prompt.").arg(days ?? 7),
            root.engine.interfaceRole);
    }

    function resumeRecall() {
        root.store.recallPausedUntil = 0;
        root.store.save();
    }
}
