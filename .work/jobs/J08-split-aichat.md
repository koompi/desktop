# J08 — split AiChat.qml into composer, transcript, commands, completion

## Files you own
- `dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/AiChat.qml`
- `dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/aiChat/ChatCommands.qml` (new)
- `.../aiChat/CommandCompletion.qml` (new)
- `.../aiChat/ChatTranscript.qml` (new)
- `.../aiChat/ChatComposer.qml` (new)
- `.../aiChat/RecallStrip.qml` (new)
- `.../aiChat/ContextMeter.qml` (new)
- `.../aiChat/testMessage.js` (new)

## Do
1. (D8) Read `AiChat.qml` fully, `SidebarLeftContent.qml:85-100`, `aiChat/AiMessage.qml` around line 490 and its `messageInputField` property, `aiChat/CommandPalette.qml`, `aiChat/ChatStatusBar.qml`.
2. (D8) `ChatCommands.qml` (QtObject): `commandGroups`, `groupTitleOf`, `noteThatItMoved`, `allCommands`, and `run(name, args) -> bool` (the dispatch half of `handleInput`). The 55-line `test` fixture (440-495) moves to `testMessage.js`.
3. (D8) `CommandCompletion.qml` (QtObject): 608-711 (`argumentCandidates`, `commandEntries`, `narrow`, `byGroup`, `updateSuggestions`) with `commands`, `query`, `entries` properties.
4. (D8) `ChatTranscript.qml` (Item): 739-902 plus `focusTranscript`, stall watchdog (497, 545-560). Public: `stallDetected`, `messageInputField` in-property (forwarded to `AiMessage`), `focusTranscript()`, `positionAtEnd()`, `pageUp()`, `pageDown()`, signals `starterChosen(text)`, `settingsRequested()`.
5. (D8) `ChatComposer.qml` (Item): 713-729, 1073-1387, history helpers 504-543. Public: `text`, `prefix`, `helpShown`, `attachMenuShown`, `suggestionsVisible`, `prefill(cmd)`, `insertText(text)`, `focusInput()`, signals `submitted(text)`, `transcriptFocusRequested()`, `pageScrollRequested(dir)`, `settingsRequested()`. The two id couplings (`messageListView` from 1168-1181, `root.focusTranscript()` at 1155) become these signals.
6. (D8) `RecallStrip.qml` (562-578 + 985-1021) and `ContextMeter.qml` (904-950).
7. (D8) `AiChat.qml` becomes root key handling (25-54), the six children, and wiring: `onSubmitted: if (!commands.run(...)) Ai.sendUserMessage(...)`. Target ≤ 200 lines.
8. `qmllint` on every file, then the live check in Acceptance 3.

## Acceptance
1. `wc -l` of all eight files (AiChat ≤ 200, none over 400).
2. A table of every `/command` (22 rows) with the result of typing it in the live sidebar: 20 that run must show the same first response line as on `main`; `attach` and `key` may be exercised only to the point of opening their UI.
3. Live: deploy to `~/.config/quickshell/koompi/modules/koompi/sidebarLeft/`, `koompi reload`, then demonstrate and paste `qs log` excerpts for: typing `/` shows the palette; Tab from the composer focuses the transcript; PageUp/PageDown from the composer scroll the transcript; a starter chip inserts its text; the stall watchdog banner still appears when `Ai` reports a stall (or say how you forced it); the recall strip appears while typing a memory-matching word.
4. `qs log -c koompi | grep -iE 'AiChat|aiChat|error|undefined' | tail -30` with no new lines versus `main`.
5. `./tests/run.sh` tail, unchanged count.

## Out of scope
- `SidebarLeftContent.qml` (the single instantiation stays `AiChat {}`), `AiMessage.qml`, `CommandPalette.qml`, `ChatStatusBar.qml`, any file under `aiChat/feedback/`.
- Adding, removing, or renaming commands; changing key bindings.

## Stop conditions
- Any needed change outside the owned list → stop and report the line.
- If the composer/transcript signal contract cannot express a behaviour (a third id coupling the map missed), stop and report it; do not reach across ids.
