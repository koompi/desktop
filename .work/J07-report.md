# J07 report: split FeedbackService.qml (AUDIT D7)

Branch `j07-split-feedback-service`, base `main` 86c616f5.
Commits: `fbe13635` (the split + test), `4f2297fa` (allow-list row dropped), plus this report.

## Outcome

Done: the split, the hub under cap, no consumer file changed, the rules test importing the module, the live deploy.
Blocked on one item that is the lead's call: `feedbackRules.js` is 461 lines against the 300-line JS cap, so `./tests/run.sh` is 78 passed, 3 skipped, 1 failed (`test_file_length.sh`), not the baseline 79/3/0.

### The block, exactly

- The job says (`.work/jobs/J07-split-feedback-service.md`, Do 2) to move lines 61-363 plus five named functions verbatim into one `feedbackRules.js`, and estimates it at "≈ 320".
- The addendum says no new file over its cap (JS 300), and `tests/test_file_length.sh:471` enforces it.
- Old lines 61-363 are 303 lines by themselves, so no single-file verbatim move can be under 300; with the five named functions it is 387, and with the three more that were needed to get the hub under 400 (below) it is 461.
- The Stop condition says any change outside the owned list stops the job. Every exit needs one:
  1. A second module under `services/ai/`, e.g. `feedbackRules.js` = reading the user's sentence and auditing the call record (old 66-325, 272 lines with header) and `feedbackWrites.js` = `tagsFor`, `provenanceOf`, `draftFrom`, `losesConflict`, `turnFrom`, `sourceKey`, `isMemorySuppressed`, `procedureKey`, `outcomeOf`, `estimateTokens`, `hashOf` (~200 lines) importing the first with `.import "feedbackRules.js" as Rules`. Both under cap; the test rewrites that one directive to an ESM import. Recommended.
  2. An allow-list row `dots/.config/quickshell/koompi/services/ai/feedbackRules.js<TAB>461`. Contradicts the addendum, and it is a new file on a ratchet meant to shrink.
  3. Keep `procedureKey`/`outcomeOf`/`estimateTokens` in HabitTable.qml and `hashOf` in HallucinationReport.qml. Still 400+ in the JS; does not clear it.

Command that clears it once the lead picks (1): none needed from me beyond the file move; the test's `PURE` list and `RULES` path are the only two things to touch.

## Deviations from the job text, stated

- Three more pure functions went into the rules than the five named: `currentTurn` became `Rules.turnFrom(conversation)`, and `sourceKey` and `isMemorySuppressed(row, suppressed)` moved alongside `losesConflict`. Without them the hub was 454 lines; with them it is 384. Each reads only plain properties, no QML type.
- `provenanceOf(record, store)` takes the translated store label from the hub instead of calling `Translation.tr` inside the module, so the module stays importable by node without stubs. Hub: `Rules.provenanceOf(record, Translation.tr("the assistant's memory store"))`.
- `precedence` and `correctionSource` are `var`s in the module; the hub re-exports them as the same readonly properties (`readonly property string precedence: Rules.precedence`). The test checks both.
- `HallucinationReport.write(turn, note)` takes the turn; the hub's `saveHallucinationReport(note)` passes `root.currentTurn()`. `lastReportPath` lives on the report object only (no consumer reads it).
- `maxTurns` lives on TrustLedger (it bounds the turn log).
- Acceptance 2 asks for 31 functions; the audit counts 26 (21 in 61-363 plus the five named), and this module has 29 (26 + the three above). 31 is not reachable from the audit's own list.

## Public surface of the hub (unchanged for consumers)

`engine`, `precedence`, `correctionSource`, signals `correctionApplied/claimUnbacked/conflictRaised`, `store`, `habits`, `ledger`, `report`, `storeDir`, `corrections`, `procedures`, `trustReport`, `recallPaused`, `activeCorrections`, `openConflicts`, `activeSuppressions`, `correctionOpen`, `pendingCorrection`, `panelOpen`, and functions `currentTurn`, `observeTurn`, `repair`, `provenanceOf`, `draftFrom`, `applyCorrection`, `markCorrected`, `suggestionFrom`, `openCorrection`, `closeCorrection`, `scanForConflicts`, `checkAgainst`, `resolveConflict`, `sourceKey`, `suppressSource`, `unsuppressSource`, `isSourceSuppressed`, `filterRecall`, `recalibrate`, `pauseRecall`, `resumeRecall`, `saveHallucinationReport`, `actionScore`, `openPanel`, `closePanel`, `togglePanel`, IPC `aifeedback`.

Part surfaces:

- `FeedbackStore`: `storeDir`, `statePath`, `proceduresPath`, `reportDir`, `corrections`, `suppressed`, `conflicts`, `turns`, `recallPausedUntil`, `groundingFloor`, `procedures`, `loaded`, `save()`, `saveProcedures()`, `loadState()`, `stateFile`, `proceduresFile`, `makeDirs`.
- `HabitTable { engine, store }`: `recordProcedures(turn)`, `actionScore(row)`.
- `TrustLedger { engine, store }`: `maxTurns`, `windowDays`, `minTurnsForGap`, `minCorrectionsForGap`, `sourcesOf(turn)`, `recordTurn(turn)`, `trustReport`, `recalibrate()`, `pauseRecall(days)`, `resumeRecall()`.
- `HallucinationReport { engine, ledger, reportDir }`: `lastReportPath`, `buildReport(turn, note)`, `write(turn, note)`, `reportFile`.

## Acceptance

### 1. `wc -l`

```
  384 dots/.config/quickshell/koompi/services/ai/FeedbackService.qml
  461 dots/.config/quickshell/koompi/services/ai/feedbackRules.js
  107 dots/.config/quickshell/koompi/services/ai/FeedbackStore.qml
   68 dots/.config/quickshell/koompi/services/ai/HabitTable.qml
  113 dots/.config/quickshell/koompi/services/ai/TrustLedger.qml
   54 dots/.config/quickshell/koompi/services/ai/HallucinationReport.qml
```

FeedbackService ≤ 400: yes (384, from 1094). feedbackRules.js: 461, over the JS cap (see the block).

### 2. Function count and the rules test

```
$ grep -n 'function ' feedbackRules.js | wc -l
29
$ bash tests/test_ai_correction.sh
found 29/29 rules: clausesOf contentWords keyWord overlaps normalise sameValue nameToken ownerNameFrom capitalise asStatement correctionFrom claimsStorage callArgs storageCalls backingCall auditTurn subjectOf contradicts losesConflict procedureKey outcomeOf estimateTokens tagsFor provenanceOf draftFrom hashOf turnFrom sourceKey isMemorySuppressed
--- BEFORE: the shipped behaviour, no verification ---
  owner name in the next request : Nimmit
  durable memories written       : 0

--- AFTER: the same transcript, the claim verified against the call record ---
  owner name in the next request : Rithy
  durable memories written       : 1
    identity    "The user's name is Rithy."  [manual-correction asserted precedence:asserted subject:owner.name]
  said to the user               : unbacked-claim -> The user's name is Rithy.

ok: the owner-name correction sticks, and it is decided by the call record
rc=0
```

The test now reads `feedbackRules.js`, strips the single `.pragma library` line, exports every name in `PURE`, and fails if any is not a function or if the file grows a `.import` (the rules must stay pure).
The three greps that pinned the verdict to the call record now point at the module; the precedence/source greps check the module's `var`s and the hub's re-export.
New checks: `turnFrom` over a six-message conversation (user text is the raw last user message, assistant texts join, calls and results collect, the audit of the read turn is `unbacked-claim`, null conversation gives null), `sourceKey` for a memory and a web source, `isMemorySuppressed` for a leading-text match, a lifted entry, and an unrelated row, and `provenanceOf` echoing the label it was handed.

### 3. Consumer grep, `main` vs branch

```
$ grep -rn 'feedback\.' dots/.config/quickshell/koompi --include='*.qml' | grep -v services/ai/ | sort > branch.txt
$ (same over `git archive main`) | sort > main.txt
$ diff main.txt branch.txt && echo IDENTICAL
IDENTICAL: 23 consumer lines, main == branch
```

`git diff --stat main..HEAD` touches only the six owned files under `services/ai/`, `tests/test_ai_correction.sh`, `tests/file-length-allow.txt` (one row removed) and this report. `Ai.qml`, `ToolRunner.qml`, `aiChat/feedback/` untouched.

### 4. Live

Pre-check before touching the live tree: the whole `koompi` tree copied to a scratch dir and run as its own instance (`qs -p /tmp/j07-qs/j07check.qml`, no windows, separate instance id), instantiating `FeedbackService { engine: null }` against the real state files:

```
J07 precedence=asserted source=manual-correction
J07 storeDir=/home/userx/.local/state/quickshell/user/ai/feedback loaded=true
J07 corrections=1 procedures=16 openConflicts=0 suppressions=1 recallPaused=false
J07 trustReport={"windowDays":7,"turns":5,"groundedTurns":5,"corrections":0,...,"needTurns":5,"needCorrections":2}
J07 sourceKey=memory|users laptop
J07 provenance={"store":"the assistant's memory store","statement":"The user's name is Rithy.","mtype":"identity","precedence":"asserted","source":"manual-correction","tags":["asserted","precedence:asserted","subject:owner.name"],"durable":true}
J07 actionScore=0.75
J07 filterRecall=[{"id":1,"text":"kept"}]
J07 isSourceSuppressed=false
J07 currentTurn=null
```

Deploy (15:12:27): backups in `/tmp/j07-backup.ABiTnp/` (`FeedbackService.qml` original, and `shell.qml`, see below); the five new files copied first, the hub last, each via `mktemp` + `mv`.
`diff -rq` branch `services/ai` vs live: identical.

Reload: there is no reload IPC in this shell (`qs -c koompi ipc show` lists none; `koompi reload` is `killall`, not used).
Quickshell's own file watcher (`Quickshell.watchFiles` is true by default, verified in the scratch instance where a rewrite of the root file reloaded it) did not fire for writes under `services/ai/`, which is loaded lazily through the `Ai` singleton.
A content-identical atomic rewrite of `shell.qml` at 15:15:43 (backed up first, `cmp` equal before and after) did not fire either.
A third in-process reload did land between 15:13 and 15:15 (`Reloading configuration...` count 2 → 3; the lines after it are `[J08]`, the other live job), and every generation loaded after 15:12:27 compiles the new files, so the live shell is on the split.
Same PID throughout (702039, launched 13:02:21); nothing killed, no sudo, session never locked.

Feedback panel via IPC (15:17:30 and again 15:17:55, closed after each):

```
$ qs -c koompi ipc call sidebarLeft open; qs -c koompi ipc call aifeedback open
$ hyprctl layers | grep -i feedback
		Layer 56105d40db50: xywh: 0 1080 1920 1200, a: 1, namespace: quickshell:aiFeedback, pid: 702039
$ qs -c koompi ipc call aifeedback report
{"windowDays":7,"turns":5,"groundedTurns":5,"corrections":0,"autoRepairs":0,"correctedTurns":0,"statedGrounding":0.45784892713482916,"measuredAccuracy":1,"gap":null,"enough":false,"overconfident":false,"minTurns":10,"minCorrections":2,"needTurns":5,"needCorrections":2}
$ qs -c koompi ipc call aifeedback close
```

Log:

```
$ qs log -c koompi | grep -iE 'feedback|error' | tail -20
 DEBUG qml: [J20 1787638364039] fingerPam completed result=0 (Success=0 Failed=1 Error=2)
  WARN scene: @modules/koompi/overview/SearchItem.qml[216:-1]: TypeError: Cannot read property 'height' of null   (x4)
  WARN scene: @modules/common/functions/StringUtils.qml[92:-1]: TypeError: Cannot read property 'length' of undefined   (x6)
  WARN scene: @modules/koompi/sidebarLeft/aiChat/MessageCodeBlock.qml[242:-1]: TypeError: Cannot read property 'thinking' of undefined
 DEBUG qml: [J08] recall strip: results=3 error="" dismissed=false
```

Every line above predates the last reload except the `[J08]` one, which is that job's own debug line.
The slice after the last `Reloading configuration` contains no line matching `feedback|error` other than it, and nothing naming `FeedbackService`, `FeedbackStore`, `HabitTable`, `TrustLedger`, `HallucinationReport` or `feedbackRules`.
Warnings from outside my directory, present before and after, left to their jobs: `overview/SearchItem.qml:216`, `functions/StringUtils.qml:92`, `aiChat/MessageCodeBlock.qml:242`, `aiChat/AiMessage.qml:153,321`, `background/Background.qml:373` (binding loop), `services/AgentUsage.qml:73`, `koompi.clock/Widget.qml` not found.

State files (`stateFile` points at `~/.local/state/quickshell/user/ai/feedback/`):

```
$ ls -la ~/.local/state/quickshell/user/ai/feedback/
-rw-r--r-- 1 userx userx  4536 2026-08-25 09:12:24 procedures.json
-rw-r--r-- 1 userx userx 16553 2026-08-25 09:12:24 state.json
```

Still present, read by the new store (79 turns, 1 correction, 1 suppression, 16 procedure rows).
Not rewritten since 09:12 because no turn has settled since then.

Not done: "send one message".
The only way to send from outside the UI is keystroke injection (`wtype`/`ydotool`) into whatever surface has keyboard focus while Rithy is using the session; there is no IPC for it and adding one is out of scope (`Ai.qml`).
So the turn-watching write path (`observeTurn` → `habits.recordProcedures` → `ledger.recordTurn` → `store.save`) is verified by the test and the scratch instance only, not by a live turn.
The next message Rithy sends will exercise it; `state.json`'s mtime moving past 09:12:24 is the check.

### 5. `./tests/run.sh`

```
==> test_file_length.sh
FAIL: dots/.config/quickshell/koompi/services/ai/feedbackRules.js is 461 lines, cap is 300; split it by concern (docs/conventions.md, File and function length)
  xx test_file_length.sh
...
78 passed, 3 skipped, 1 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
failed: test_file_length.sh
```

Baseline was 79/3/0; the one failure is the block above and nothing else.
`test_ai_correction.sh` and `test_qml_layering.sh` pass (no new file imports `qs.modules.koompi`/`waffle`; `TrustLedger`, `HallucinationReport` and the hub import `qs.services` and the shared `grounding.js` only).

## Cleanup state

- `/tmp/j07-backup.ABiTnp/`: `FeedbackService.qml` (the 1094-line original) and `shell.qml` (identical to what is live). Restore the hub with `cp /tmp/j07-backup.ABiTnp/FeedbackService.qml ~/.config/quickshell/koompi/services/ai/ && rm ~/.config/quickshell/koompi/services/ai/{FeedbackStore,HabitTable,TrustLedger,HallucinationReport}.qml ~/.config/quickshell/koompi/services/ai/feedbackRules.js`.
- Scratch tree `/tmp/j07-qs` removed.
