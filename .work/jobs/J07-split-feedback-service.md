# J07 — split FeedbackService.qml: rules to JS, stores to objects

## Files you own
- `dots/.config/quickshell/koompi/services/ai/FeedbackService.qml`
- `dots/.config/quickshell/koompi/services/ai/feedbackRules.js` (new)
- `dots/.config/quickshell/koompi/services/ai/FeedbackStore.qml` (new)
- `dots/.config/quickshell/koompi/services/ai/HabitTable.qml` (new)
- `dots/.config/quickshell/koompi/services/ai/TrustLedger.qml` (new)
- `dots/.config/quickshell/koompi/services/ai/HallucinationReport.qml` (new)
- `tests/test_ai_correction.sh`

## Do
1. (D7) Read `FeedbackService.qml` fully, `services/Ai.qml:180-245`, `services/ai/ToolRunner.qml:280-290`, `tests/test_ai_correction.sh`, `tests/test_qml_layering.sh`, and `modules/koompi/sidebarLeft/aiChat/grounding.js` (the existing pattern for a pure-JS module).
2. (D7) Move the pure rules (lines 61-363 plus `tagsFor`, `provenanceOf`, `draftFrom`, `hashOf`, `losesConflict`) verbatim into `feedbackRules.js`; import as `Rules` and call through. No forwarders: update `tests/test_ai_correction.sh:15` (and the lift at 57-75) to read the `.js` file instead.
3. (D7) Extract `FeedbackStore.qml` (persistence 997-1072: `save`, `saveProcedures`, `_readJson`, `loadState`, `stateFile`, `proceduresFile`, `makeDirs`, and the arrays/`FileView`s they own), `HabitTable.qml` (941-991), `TrustLedger.qml` (794-888), `HallucinationReport.qml` (890-936). Each is a `QtObject` (or the base the existing services use) with the public surface named in `.work/AUDIT.md` D7.
4. (D7) `FeedbackService.qml` keeps the hub (turn watching 366-496, correction path 499-643, conflicts/suppression/`filterRecall` 646-792, panel/IPC 1076-1092) and instantiates the four objects. Its public members stay exactly what `Ai.qml:186-206` re-exports plus `filterRecall`, `procedures`, `actionScore`, `storeDir`, `panelOpen`, `correctionOpen`, `pendingCorrection`. No consumer file changes.
5. `./tests/run.sh` (test_ai_correction and test_qml_layering are the critics), then the live check in Acceptance 4.

## Acceptance
1. `wc -l` of all six files (FeedbackService ≤ 400; rules.js ≈ 320).
2. `grep -n 'function ' feedbackRules.js | wc -l` = 31, and `tests/test_ai_correction.sh` output showing every named function found and its assertions passing.
3. `grep -rn 'feedback\.' dots/.config/quickshell/koompi --include='*.qml' | grep -v services/ai/` diffed against the same grep on `main`: identical (proof no consumer changed).
4. Live: deploy `services/ai/` to `~/.config/quickshell/koompi/services/ai/`, `koompi reload`, open the left sidebar AI tab, send one message, open the feedback panel (`Ai.feedback.openPanel` via the UI), paste `qs log -c koompi | grep -iE 'feedback|error' | tail -20` showing no errors, and `ls ~/.local/state/quickshell/` (or wherever `stateFile` points) showing the state file still written.
5. `./tests/run.sh` tail, unchanged count.

## Out of scope
- `Ai.qml`, `ToolRunner.qml`, any file under `aiChat/feedback/`. If one needs a change, the split is wrong; stop.
- Behaviour, thresholds, wording.

## Stop conditions
- Any change required outside the owned list → stop and report the exact line.
- If `test_qml_layering.sh` fails because a new file imports `qs.modules.*`, fix the import, never the test.
