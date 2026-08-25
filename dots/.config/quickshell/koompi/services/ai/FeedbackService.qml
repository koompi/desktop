pragma ComponentBehavior: Bound

import qs.services
import "feedbackRules.js" as Rules
import Quickshell.Io
import QtQuick

/**
 * The correction loop. `engine` is the Ai facade.
 *
 * Its first job is the one the live session exposed: a turn that says it stored
 * something, when nothing was stored. The check is made against the turn's tool
 * calls, never against its prose - the prose is only what raises the question.
 * What gets stored is read out of the *user's* sentence, because that is the
 * only text in the turn whose author knows the fact.
 *
 * Everything it writes carries `precedence: asserted`, and an asserted value is
 * never silently replaced by a later contradicting memory: the conflict is put
 * in front of the user instead.
 */
QtObject {
    id: root

    property QtObject engine

    readonly property string precedence: Rules.precedence
    readonly property string correctionSource: Rules.correctionSource

    signal correctionApplied(var record)
    signal claimUnbacked(var audit)
    signal conflictRaised(var conflict)

    // The parts. The rules are feedbackRules.js; the state is the store; the
    // ledger, the habit table and the report each own one concern.
    readonly property FeedbackStore store: FeedbackStore {}
    readonly property HabitTable habits: HabitTable { engine: root.engine; store: root.store }
    readonly property TrustLedger ledger: TrustLedger { engine: root.engine; store: root.store }
    readonly property HallucinationReport report: HallucinationReport { engine: root.engine; ledger: root.ledger; reportDir: root.store.reportDir }

    readonly property string storeDir: root.store.storeDir
    readonly property var corrections: root.store.corrections
    readonly property var procedures: root.store.procedures
    readonly property var trustReport: root.ledger.trustReport
    readonly property bool recallPaused: root.store.recallPausedUntil > Date.now()

    readonly property var activeCorrections: root.store.corrections.filter(c => c.active !== false && c.scope !== "once")

    /* ------------------------------------------------------------------ *
     * Watching turns
     * ------------------------------------------------------------------ */

    property string _lastAuditedId: ""
    property int _settleTries: 0

    // `responseFinished` fires from the stream, while curl is still up and the
    // tool calls of the turn have not run yet. The audit waits for the turn to
    // actually settle instead.
    readonly property Timer settleTimer: Timer {
        interval: 250
        repeat: false
        onTriggered: root.observeTurn()
    }

    readonly property Connections engineWatch: Connections {
        target: root.engine
        function onResponseFinished() {
            root._settleTries = 0;
            root.settleTimer.restart();
        }
        // A turn that ends by timing out, or by being cancelled, never reaches
        // `responseFinished`. The engine going idle is the other way in.
        function onRequestActiveChanged() {
            if (root.engine?.requestActive) return;
            root._settleTries = 0;
            root.settleTimer.restart();
        }
    }

    // Everything since the last thing the user typed, read off the conversation.
    function currentTurn() { return Rules.turnFrom(root.engine?.conversation); }

    function observeTurn() {
        const turn = root.currentTurn();
        if (!turn || turn.messageId.length === 0) return;
        // Waiting on an approval click is not a settled turn, and it ends in
        // another response, which re-arms this by itself.
        if (turn.pending) return;
        if (!turn.done || root.engine?.requestActive) {
            if (root._settleTries++ < 120) root.settleTimer.restart();
            return;
        }
        if (turn.messageId === root._lastAuditedId) return;
        root._lastAuditedId = turn.messageId;

        root.habits.recordProcedures(turn);
        root.ledger.recordTurn(turn);

        const audit = Rules.auditTurn(turn);
        if (audit.verdict === "unbacked-claim" || audit.verdict === "silent-drop") {
            root.claimUnbacked({ "audit": audit, "turn": turn });
            root.repair(audit, turn);
        }
        root.scanForConflicts();
    }

    function repair(audit, turn) {
        const correction = audit.correction;
        const alreadyRight = correction.kind === "owner-name"
            && Rules.sameValue(root.engine?.ownerName ?? "", correction.value)
            && root.activeCorrections.some(entry => entry.subject === "owner.name" && Rules.sameValue(entry.value, correction.value));
        if (alreadyRight) return;

        root.applyCorrection({
            "kind": correction.kind,
            "value": correction.value,
            "statement": correction.statement,
            "mtype": correction.mtype,
            "subject": correction.subject,
            "claim": (turn.assistantText ?? "").split("\n")[0].slice(0, 200),
            "scope": "durable",
            "origin": audit.verdict === "unbacked-claim" ? "auto-repair-after-claim" : "auto-repair",
            "messageId": turn.messageId
        }, (record, error) => {
            const said = audit.verdict === "unbacked-claim"
                ? Translation.tr("I said I had noted that, and I had not. Stored now: %1").arg(record.statement)
                : Translation.tr("Stored, so it outlasts this conversation: %1").arg(record.statement);
            const tail = error && error.length > 0
                ? Translation.tr(" (memory refused it: %1)").arg(error)
                : "";
            root.engine.addMessage(said + tail, root.engine.interfaceRole);
        });
    }

    /* ------------------------------------------------------------------ *
     * Writing a correction
     * ------------------------------------------------------------------ */

    // What the modal shows before it writes anything. Same object the write
    // uses. The store's label is the one string in the rules that is shown to
    // the user, so it is translated here and handed in.
    function provenanceOf(record) {
        return Rules.provenanceOf(record, Translation.tr("the assistant's memory store"));
    }

    function draftFrom(text, claim) { return Rules.draftFrom(text, claim); }

    function applyCorrection(input, callback) {
        const record = {
            "id": `corr-${Date.now()}-${root.store.corrections.length}`,
            "kind": input.kind ?? "fact",
            "value": input.value ?? "",
            "statement": input.statement ?? "",
            "mtype": input.mtype ?? "fact",
            "subject": input.subject ?? "",
            "claim": input.claim ?? "",
            "scope": input.scope ?? "durable",
            "origin": input.origin ?? "user-modal",
            "precedence": root.precedence,
            "source": root.correctionSource,
            "sessionId": root.engine?.sessionId ?? "",
            "messageId": input.messageId ?? "",
            "at": Date.now(),
            "memoryId": -1,
            "memoryError": "",
            "active": true
        };

        // The name is shell state, not a memory, and it is what {OWNER} reads.
        if (record.kind === "owner-name" && root.engine?.setOwnerName) root.engine.setOwnerName(record.value);

        root.store.corrections = [...root.store.corrections, record];
        root.markCorrected(record);
        root.store.save();

        if (record.scope === "once") {
            root.correctionApplied(record);
            if (callback) callback(record, "");
            return record;
        }

        MemoryService.remember(record.statement, record.mtype, Rules.tagsFor(record), root.correctionSource, (response, error) => {
            const index = root.store.corrections.findIndex(entry => entry.id === record.id);
            if (index >= 0) {
                const updated = root.store.corrections.slice();
                updated[index] = Object.assign({}, updated[index], {
                    "memoryId": response?.memory_id ?? -1,
                    "memoryError": error ?? ""
                });
                root.store.corrections = updated;
                root.store.save();
            }
            root.correctionApplied(record);
            if (callback) callback(record, error ?? "");
        });
        return record;
    }

    function markCorrected(record) {
        if (!record.messageId) return;
        const index = root.store.turns.findIndex(entry => entry.messageId === record.messageId);
        if (index < 0) return;
        const updated = root.store.turns.slice();
        updated[index] = Object.assign({}, updated[index], { "corrected": true });
        root.store.turns = updated;
    }

    /* ---- the modal ---- */

    property bool correctionOpen: false
    property var pendingCorrection: null

    // What the user's last turn already said, so the modal opens knowing it
    // rather than asking them to type it a second time.
    function suggestionFrom() {
        const correction = Rules.correctionFrom(root.currentTurn()?.userText ?? "");
        return correction ? correction.statement : "";
    }

    // `target` is {claim, messageId, source} - the answer or one citation row.
    function openCorrection(target) {
        root.pendingCorrection = {
            "claim": target?.claim ?? "",
            "messageId": target?.messageId ?? "",
            "source": target?.source ?? null,
            "suggested": target?.suggested ?? root.suggestionFrom()
        };
        root.correctionOpen = true;
    }

    function closeCorrection() {
        root.correctionOpen = false;
        root.pendingCorrection = null;
    }

    /* ------------------------------------------------------------------ *
     * A correction outranks inference
     * ------------------------------------------------------------------ */

    property double _lastConflictScan: 0

    function scanForConflicts() {
        if (root.activeCorrections.length === 0) return;
        if (Date.now() - root._lastConflictScan < 30000) return;
        root._lastConflictScan = Date.now();
        MemoryService.list(200, (response, error) => {
            if (!response) return;
            root.checkAgainst(response.results ?? []);
        });
    }

    // An asserted value is never rewritten by what arrives later. The later row
    // keeps existing; what changes is that the user is told the two disagree.
    function checkAgainst(rows) {
        const raised = [];
        for (const correction of root.activeCorrections) {
            if (correction.subject.length === 0) continue;
            for (const row of rows) {
                if (row.source === root.correctionSource) continue;
                if (row.id === correction.memoryId) continue;
                if (!Rules.contradicts(correction.subject, correction.value, row.text ?? "")) continue;
                const key = `${correction.id}:${row.id}`;
                if (root.store.conflicts.some(entry => entry.key === key)) continue;
                raised.push({
                    "key": key,
                    "subject": correction.subject,
                    "asserted": correction.statement,
                    "assertedAt": correction.at,
                    "incoming": row.text ?? "",
                    "incomingId": row.id,
                    "incomingSource": row.source ?? "",
                    "at": Date.now(),
                    "resolved": false
                });
            }
        }
        if (raised.length === 0) return;
        root.store.conflicts = [...root.store.conflicts, ...raised];
        root.store.save();
        for (const conflict of raised) {
            root.conflictRaised(conflict);
            root.engine.addMessage(
                Translation.tr("You told me: %1\nSomething else in my memory says: %2\nI am keeping what you told me. Open the correction panel to drop the other one.")
                    .arg(conflict.asserted).arg(conflict.incoming),
                root.engine.interfaceRole);
        }
    }

    function resolveConflict(key, dropIncoming) {
        const index = root.store.conflicts.findIndex(entry => entry.key === key);
        if (index < 0) return;
        const conflict = root.store.conflicts[index];
        const updated = root.store.conflicts.slice();
        updated[index] = Object.assign({}, conflict, { "resolved": true, "resolvedAt": Date.now() });
        root.store.conflicts = updated;
        root.store.save();
        if (dropIncoming && conflict.incomingId >= 0) MemoryService.forget(conflict.incomingId, null);
    }

    readonly property var openConflicts: root.store.conflicts.filter(entry => !entry.resolved)

    /* ------------------------------------------------------------------ *
     * Suppression: excluded from retrieval, never deleted
     * ------------------------------------------------------------------ */

    function sourceKey(source) { return Rules.sourceKey(source); }

    function suppressSource(source) {
        const key = root.sourceKey(source);
        if (root.store.suppressed.some(entry => entry.key === key && entry.active)) return;
        // A memory row's id is the exact handle; the name is a truncated copy of
        // its text, so resolve it while the recall that produced it is still here.
        let memoryId = -1;
        if ((source?.type ?? "") === "memory") {
            const rows = MemoryService.lastRecall ?? [];
            const wanted = String(source?.name ?? "").replace(/…$/, "");
            for (const row of rows) {
                if (String(row.text ?? "").indexOf(wanted) === 0) { memoryId = row.id; break; }
            }
        }
        root.store.suppressed = [...root.store.suppressed, {
            "key": key,
            "type": source?.type ?? "memory",
            "name": source?.name ?? "",
            "detail": source?.detail ?? "",
            "url": source?.url ?? "",
            "memoryId": memoryId,
            "at": Date.now(),
            "active": true
        }];
        root.store.save();
    }

    function unsuppressSource(key) {
        const index = root.store.suppressed.findIndex(entry => entry.key === key);
        if (index < 0) return;
        const updated = root.store.suppressed.slice();
        updated[index] = Object.assign({}, updated[index], { "active": false, "liftedAt": Date.now() });
        root.store.suppressed = updated;
        root.store.save();
    }

    function isSourceSuppressed(source) {
        const key = root.sourceKey(source);
        return root.store.suppressed.some(entry => entry.key === key && entry.active);
    }

    // What the turn is allowed to be given. Suppression, the pause and a lost
    // conflict all land here, so nothing has to be deleted for any of them.
    function filterRecall(results) {
        const rows = Array.isArray(results) ? results : [];
        if (root.recallPaused) return [];
        return rows.filter(row => !Rules.isMemorySuppressed(row, root.store.suppressed) && !Rules.losesConflict(row, root.store.conflicts));
    }

    readonly property var activeSuppressions: root.store.suppressed.filter(entry => entry.active)

    /* ---- measuring, reporting, the habit table: called through ---- */

    function recalibrate() { root.ledger.recalibrate(); }
    function pauseRecall(days) { root.ledger.pauseRecall(days); }
    function resumeRecall() { root.ledger.resumeRecall(); }
    function saveHallucinationReport(note) { return root.report.write(root.currentTurn(), note); }
    function actionScore(row) { return root.habits.actionScore(row); }

    /* ---- windows ---- */

    property bool panelOpen: false

    function openPanel() { root.panelOpen = true; }
    function closePanel() { root.panelOpen = false; }
    function togglePanel() { root.panelOpen = !root.panelOpen; }

    // The windows themselves are loaded by the panel family, not from here. A
    // service that imports a UI package makes the two circular, and QML resolves
    // that by reporting FeedbackService as not a type at all.

    readonly property IpcHandler ipc: IpcHandler {
        target: "aifeedback"
        function open(): void { root.openPanel(); }
        function close(): void { root.closePanel(); }
        function toggle(): void { root.togglePanel(); }
        function report(): string { return JSON.stringify(root.trustReport); }
    }
}
