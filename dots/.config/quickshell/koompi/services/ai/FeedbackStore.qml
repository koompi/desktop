import qs.modules.common
import qs.modules.common.functions as CF
import Quickshell.Io
import QtQuick

/**
 * What the correction loop keeps on disk: the ledger (corrections, suppressed
 * sources, conflicts, the turn log, the recall pause and the grounding floor)
 * in `state.json`, and the habit table in `procedures.json`. This owns the
 * arrays, the paths, the FileViews and the mkdir that has to run before either
 * file is read. It decides nothing; FeedbackService and its parts write here.
 */
QtObject {
    id: root

    readonly property string storeDir: CF.FileUtils.trimFileProtocol(`${Directories.state}/user/ai/feedback`)
    readonly property string statePath: `${root.storeDir}/state.json`
    readonly property string proceduresPath: `${root.storeDir}/procedures.json`
    // 36:238 - the bundle is written here and never sent anywhere.
    readonly property string reportDir: CF.FileUtils.trimFileProtocol(`${Directories.home}/.local/share/koompi-ai/reports`)

    property var corrections: []
    property var suppressed: []
    property var conflicts: []
    property var turns: []
    property double recallPausedUntil: 0
    property real groundingFloor: 0
    property var procedures: []
    property bool loaded: false

    function save() {
        if (!root.loaded) return;
        stateFile.setText(JSON.stringify({
            "version": 1,
            "corrections": root.corrections,
            "suppressed": root.suppressed,
            "conflicts": root.conflicts,
            "turns": root.turns,
            "recallPausedUntil": root.recallPausedUntil,
            "groundingFloor": root.groundingFloor
        }, null, 2));
    }

    function saveProcedures() {
        proceduresFile.setText(JSON.stringify({
            "version": 1,
            "table": "procedures",
            "columns": ["id", "tool_name", "input_pattern", "success_count", "failure_count",
                "total_tokens_est", "last_used", "session_id", "approved"],
            "unique": ["tool_name", "input_pattern"],
            "rows": root.procedures
        }, null, 2));
    }

    function _readJson(view) {
        try {
            const text = view.text();
            if (!text || text.trim().length === 0) return null;
            return JSON.parse(text);
        } catch (e) {
            return null;
        }
    }

    function loadState() {
        const state = root._readJson(stateFile);
        if (state) {
            root.corrections = state.corrections ?? [];
            root.suppressed = state.suppressed ?? [];
            root.conflicts = state.conflicts ?? [];
            root.turns = state.turns ?? [];
            root.recallPausedUntil = state.recallPausedUntil ?? 0;
            root.groundingFloor = state.groundingFloor ?? 0;
        }
        const table = root._readJson(proceduresFile);
        if (table) root.procedures = table.rows ?? [];
        root.loaded = true;
    }

    // blockAllReads so a read after a write never returns the previous file,
    // the way ThreadStore learned to.
    readonly property FileView stateFile: FileView {
        path: root.statePath
        blockAllReads: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }

    readonly property FileView proceduresFile: FileView {
        path: root.proceduresPath
        blockAllReads: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
        watchChanges: false
    }

    // FileView writes a file, not a directory tree. Nothing is read until this
    // has run, so a first install cannot lose its first correction.
    readonly property Process makeDirs: Process {
        running: true
        command: ["mkdir", "-p", root.storeDir, root.reportDir]
        onExited: root.loadState()
    }
}
