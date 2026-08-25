import qs.services
import "feedbackWrites.js" as Writes
import "../../modules/koompi/sidebarLeft/aiChat/grounding.js" as Grounding
import Quickshell.Io
import QtQuick

/**
 * The hallucination bundle. Written locally under `reportDir`, never sent
 * (36:238): the prompt hash, the model, the redacted source list and the
 * grounding of the turn, plus whatever the user typed. `engine` is the Ai
 * facade; `ledger` supplies what the turn was actually given.
 */
QtObject {
    id: root

    property QtObject engine
    property TrustLedger ledger
    property string reportDir

    property string lastReportPath: ""

    function buildReport(turn, note) {
        const grounding = Grounding.computeGrounding(root.ledger.sourcesOf(turn), turn?.assistantText ?? "");
        return {
            "prompt_hash": Writes.hashOf(root.engine?.systemPrompt ?? ""),
            "model": root.engine?.currentModelId ?? "",
            "retrieved": root.ledger.sourcesOf(turn).map(source => ({
                "type": source.type,
                "score": source.score ?? 0,
                "redacted": true
            })),
            "grounding": grounding ? Number(grounding.value.toFixed(3)) : null,
            "note": note ?? "",
            "at": new Date().toISOString(),
            "dest": root.reportDir,
            "sent": false
        };
    }

    // `turn` is what FeedbackService.currentTurn() returned for the answer on screen.
    function write(turn, note) {
        const report = root.buildReport(turn, note);
        const path = `${root.reportDir}/${Date.now()}.json`;
        reportFile.path = Qt.resolvedUrl(path);
        reportFile.setText(JSON.stringify(report, null, 2));
        root.lastReportPath = path;
        root.engine.addMessage(
            Translation.tr("Saved a local report to %1. Nothing was sent anywhere.").arg(path),
            root.engine.interfaceRole);
        return path;
    }

    readonly property FileView reportFile: FileView {}
}
