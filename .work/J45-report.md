# J45 report — switch model inside the sidebar; `/key` and `/model` stop pointing at Settings

Branch `j45-model-picker-in-sidebar`, from main at `7163ccd4`.
Files touched: `sidebarLeft/AiChat.qml`, `aiChat/ChatComposer.qml`, `aiChat/ChatCommands.qml`, `aiChat/ChatTranscript.qml`,
`aiChat/composer/ChatStatusBar.qml`, new `aiChat/composer/ModelPicker.qml`, new `tests/test_ai_model_picker.sh`,
the `allowed=` block of `.github/workflows/tests.yml`. Nothing under `services/ai/`, `modules/settings/`, `SettingsPages.qml`
or `koompi-settings` changed. `docs/navigation.md` unchanged: it lists sidebar surfaces, bar buttons and keybinds, not the
chat's controls (no row for the attach menu or the help sheet either), so a picker row has nowhere to go.

## Fact sheet, verified
All four facts held: the chip (`ChatComposer.qml:326-332`) and the status-bar name (`ChatStatusBar.qml:158-172`) both went
`settingsRequested → AiChat.openAiSettings → SettingsPages.open`; the no-key button said "Settings"; `/model` took `args[0]`
and `/key` took `args[0]` with the "lives in Settings > AI now" note; `AiModel` has `name` and `description`, and
`CommandCompletion.argumentCandidates("model")` already reads both, so the picker needs no shape `Ai.modelList` cannot give.

## What was built
- **`ModelPicker.qml`** (234 lines): a `FocusScope` sheet in the style of `KeyboardHelpSheet`/`AttachMenu` — a heading with a
  close button, then one `RippleButton` row per model (check mark on the current one, name, description, elided). Input is
  `models: [{ id, name, description }]` and `currentId`; output is `picked(string id)` and `dismissed()`. Opening sets the
  highlight on the current model; Up/Down move it (clamped, scrolled into view past `maxHeight` 260), Enter picks, Escape
  dismisses, hover follows the mouse, a click picks. Losing active focus while visible (Tab away, the sidebar closing) also
  dismisses. The keys call `moveSelection(step)` and `activateSelected()`, which is what the probe drives. No `Ai.` reference.
- **`AiChat.qml`**: instantiates the picker above the composer, feeds it `Ai.modelList.map(...)` and `Ai.currentModelId`,
  and wires `picked → Ai.setModel(id)`. A full-size `MouseArea` (z 1, only while the picker is shown) is the click-outside:
  a press inside the picker is let through (`mouse.accepted = false`), a press anywhere else emits `dismissed` and is
  swallowed, the way a popup eats the click that closes it. Whenever `modelPickerShown` goes false the composer regains focus.
  `openAiSettings` and the two `onSettingsRequested` wirings are gone (nothing emits the signal any more).
- **`ChatComposer.qml`**: `modelPickerShown` property; the chip toggles it; tooltip is "Answering: X / Click to switch model";
  Escape closes the picker with the other sheets; the `settingsRequested` signal is removed (no caller left).
- **`ChatStatusBar.qml`**: `settingsRequested` replaced by `modelPickerRequested` (model name click) and `keyRequested`
  (the no-key button, now "Set key", with a tooltip saying the key goes to the keyring). The tooltip's last line is
  "Click to switch model". The red "%1 needs an API key" text stays. `ChatTranscript.qml` forwards both signals.
- **`ChatCommands.qml`**: `/key` takes `args.join(" ").trim()` (`get` still prints the masked key; empty still lands in
  `setApiKey`'s advice path); `/model` with nothing opens the picker via a new `modelPickerRequested` signal, with an
  argument calls `Ai.setModel(args[0].trim())` as before; both lose `moved: true` and the `noteThatItMoved` call.
  `noteThatItMoved` stays: `/prompt`, `/endpoint` and `/temp` still use it. The "config" group title still reads
  "Settings — now in Settings > AI"; it is the title for those three, and the job named only the two notes.

## How a user switches model (three clicks or fewer)
1. Click the model chip at the bottom-left of the composer (or the model name in the status bar at the top of the transcript).
2. Click the model in the sheet that opens above the composer. Done: two clicks, the sheet closes, the composer has focus and
   the transcript shows "Model set to …". Keyboard: `/model` Enter, Down/Up, Enter — or the chip, then arrows and Enter.
   Escape, the sheet's ✕, the chip again or a click anywhere else closes it without changing anything.
No key: the status bar says "X needs an API key" with a "Set key" button; clicking it puts `/key ` in the composer,
the user pastes the key and presses Enter, and the existing command stores it in the keyring.

## Acceptance
### 1. Probe output and static lines (`nice -n 19 ionice -c 3 tests/test_ai_model_picker.sh`, exit 0)
```
ok   static: chip and status-bar name open the picker, neither names Settings > AI
ok   static: no-key button reads Set key and prefills /key
ok   static: /key takes the whole line, /model alone opens the picker, moved notes gone
ok   static: picker takes models, reports picked, knows no Ai; every touched file under 400 lines
ok   qmllint: the six touched files parse without errors
PASS open: three rows  got=3
PASS open: row names  got=["Alpha","Beta","Gamma"]
PASS open: only the current row is marked  got=[false,true,false]
PASS open: highlight starts on the current row  got=1
PASS down: highlight moves to 2  got=2
PASS down: stops at the last row  got=2
PASS enter: picked carries the highlighted id  got=["gamma"]
PASS up: highlight moves to 0  got=0
PASS up: stops at the first row  got=0
PASS click: picked carries the row's id  got=["gamma","alpha"]
PASS reopen: mark follows currentId  got=[false,false,true]
PASS reopen: highlight follows currentId  got=2
PASS nothing dismissed it  got=0
PROBE OK
ok   model picker: three rows, the current one marked, keys and a click report the id through picked
```
### 2. Sibling tests (all exit 0)
```
== test_ai_threads.sh (tail)
PASS no thread holds another thread's messages  mixed=0
PROBE OK
ok: 3 threads created, reloaded from disk and read back without crossing
== file_length
ok: 933 files under cap, 34 allow-listed and not grown
== keybind
keybind descriptions: all 149 binds described or hidden
```
Line counts of every touched QML file (cap 400):
```
  218 AiChat.qml
  396 aiChat/ChatComposer.qml
  399 aiChat/ChatCommands.qml
  226 aiChat/ChatTranscript.qml
  285 aiChat/composer/ChatStatusBar.qml
  234 aiChat/composer/ModelPicker.qml
 1758 total
```
### 3. qmllint (Qt 6, `/usr/lib/qt6/bin/qmllint -I <root with qs symlink> -I /usr/lib/qt6/qml`)
0 errors in each of the six files (the test's qmllint step is the check; the only output is the tree-wide
"Failed to import qs" warnings every file in this shell gets).
### 4. No screenshot; the three-click description is above.

## Verified and not verified
- The probe runs the real `ModelPicker.qml` under `qs -p` (no window, no Ai singleton, XDG in a temp dir, `secret-tool` and
  `ollama` shimmed to exit 1): 13 checks, PROBE OK. Key events themselves cannot be delivered without a window; the probe
  calls the functions the `Keys.onPressed` branches call, and the static half checks those branches exist.
- Not exercised: the live sidebar (the lead does `koompi reload`). What to look at there: the chip opens the sheet with focus
  on it, arrows move the highlight, Enter switches and the composer is focused again, a click on the transcript closes it.
- Probe log carries two pre-existing warnings unrelated to this job (`MaterialCookie` unresolvable js imports,
  `implicitWidth` override in a widget) and the expected missing `config.json`/translation reads in the temp XDG dir.

## Gaps for the lead
- `ModelRegistry.setModel`'s own usage line says `/model remote NAME`, but `setModel("remote")` ignores anything after it and
  `args[0]` never carried it; unchanged here (J44 owns the registry). The picker only ever passes a bare id.
- `/model` completion (`CommandCompletion.qml`) is unchanged and still lists `Ai.modelList`; no edit was needed.

## Round 2 (lead's review of `444d9c9d`)
1. **Seeding survived the owner's handler.** `ModelPicker.qml` seeded `selectedIndex` in `onVisibleChanged`, and
   `AiChat.qml` sets `onVisibleChanged` on the instance to hand focus over, which replaced it: nothing highlighted on open,
   Enter a no-op, Down to row 0. The seeding now lives in a `Connections { target: root }` block inside the component, which
   an instance handler cannot replace; `revealRow` runs from there too. The probe instantiates the picker with the same
   instance-level `onVisibleChanged: if (visible) Qt.callLater(picker.focusFirst)` that `AiChat.qml` uses, so "highlight
   starts on the current row" and "reopen: highlight follows currentId" now exercise the real wiring; a static check fails the
   test if a top-level `onVisibleChanged:` ever comes back into `ModelPicker.qml`.
2. **Accessibility.** Root: `Accessible.role: Accessible.List`, `Accessible.name: "Which model answers"`. Rows:
   `Accessible.role: Accessible.ListItem`, `Accessible.name` (with ", current" on the marked one), `Accessible.description`,
   `Accessible.selected` bound to the highlight, so Up/Down announce the row. Rows keep `focusPolicy: NoFocus` (keys are
   handled by the scope); the probe checks `Accessible.selected` follows the highlight and the role and name are set.

Gates (`nice -n 19 ionice -c 3`, all exit 0):
```
ok   static: chip and status-bar name open the picker, neither names Settings > AI
ok   static: no-key button reads Set key and prefills /key
ok   static: /key takes the whole line, /model alone opens the picker, moved notes gone
ok   static: picker takes models, reports picked, knows no Ai, seeds without onVisibleChanged, has list roles; every touched file under 400 lines
ok   qmllint: the six touched files parse without errors
PASS open: three rows  got=3
PASS open: row names  got=["Alpha","Beta","Gamma"]
PASS open: only the current row is marked  got=[false,true,false]
PASS open: highlight starts on the current row  got=1
PASS open: rows read as list items with the highlight selected  got=[false,true,false]
PASS open: current row says so to a screen reader  got="Beta, current"
PASS open: the sheet is a named list  got=[true,true]
PASS down: highlight moves to 2  got=2
PASS down: Accessible.selected follows  got=[false,false,true]
PASS down: stops at the last row  got=2
PASS enter: picked carries the highlighted id  got=["gamma"]
PASS up: highlight moves to 0  got=0
PASS up: stops at the first row  got=0
PASS click: picked carries the row's id  got=["gamma","alpha"]
PASS reopen: mark follows currentId  got=[false,false,true]
PASS reopen: highlight follows currentId  got=2
PASS nothing dismissed it  got=0
PROBE OK
ok   model picker: three rows, the current one marked, keys and a click report the id through picked
== test_ai_threads exit=0
PROBE OK
ok: 3 threads created, reloaded from disk and read back without crossing
== test_file_length exit=0
ok: 934 files under cap, 34 allow-listed and not grown
== test_keybind_descriptions exit=0
keybind descriptions: all 149 binds described or hidden
```
qmllint: 0 errors in the six files (the test's step). `ModelPicker.qml` is 244 lines; the other touched files are unchanged
since round 1. Still unverified live: what a screen reader actually announces under the sidebar's layer-shell window.

## Round 3 (lead's review of `c6257495`)
1. **Reveal after geometry.** `revealRow` now treats "no sizes yet" as not done: with `row.height` 0, `list.height` 0, or a row
   past the first still at `y` 0, it records `pendingReveal` and returns. `retryReveal()` runs from the Flickable's
   `heightChanged`/`contentHeightChanged` and from every row's `yChanged`/`heightChanged`, so whichever layout is polished
   last (the sheet's column sizing the list, or the row column placing the rows) completes the reveal; the pending index is
   cleared only once a reveal ran with real sizes. Seeding sets `pendingReveal` before the `Qt.callLater`, so a callLater
   that lands early is never the last word.
2. **Hover only on movement.** `onHoveredChanged` is gone. Each row has a `MouseArea` (`acceptedButtons: NoButton`,
   `hoverEnabled`) whose `onPositionChanged` calls `noteHover(index, point)` with the pointer mapped into the picker's own
   coordinates; `noteHover` ignores a point equal to the last one seen. The list scrolling under a resting pointer re-hovers
   a row at the same picker-relative point, so an arrow key's selection stays; a real pointer move selects as before.

Probe additions (a second picker with 12 fake models, current one last, opened with the owner's instance-level
`onVisibleChanged`): after open the current row is inside the viewport and row 0 is not, `pendingReveal` is -1, Up×11 brings
row 0 into view; a forced pending reveal runs on a row geometry change; `noteHover` at a moved point selects, Down×3 then the
same point again keeps 3, a new point selects. What the probe cannot do: run the layout polish loop (no window), so the first-open
zero-geometry moment is exercised through the forced pending reveal and the row-geometry retry, not by observing the live race;
and it cannot move a real pointer, so the hover rule is checked through `noteHover` with the static check that the rows call it
from `onPositionChanged` and never from `hovered`.

Gates (`nice -n 19 ionice -c 3`, all exit 0):
```
ok   static: chip and status-bar name open the picker, neither names Settings > AI
ok   static: no-key button reads Set key and prefills /key
ok   static: /key takes the whole line, /model alone opens the picker, moved notes gone
ok   static: picker takes models, reports picked, knows no Ai, seeds without onVisibleChanged, has list roles; every touched file under 400 lines
ok   qmllint: the six touched files parse without errors
PASS open: three rows  got=3
PASS open: row names  got=["Alpha","Beta","Gamma"]
PASS open: only the current row is marked  got=[false,true,false]
PASS open: highlight starts on the current row  got=1
PASS open: rows read as list items with the highlight selected  got=[false,true,false]
PASS open: current row says so to a screen reader  got="Beta, current"
PASS open: the sheet is a named list  got=[true,true]
PASS down: highlight moves to 2  got=2
PASS down: Accessible.selected follows  got=[false,false,true]
PASS down: stops at the last row  got=2
PASS enter: picked carries the highlighted id  got=["gamma"]
PASS up: highlight moves to 0  got=0
PASS up: stops at the first row  got=0
PASS click: picked carries the row's id  got=["gamma","alpha"]
PASS reopen: mark follows currentId  got=[false,false,true]
PASS reopen: highlight follows currentId  got=2
PASS nothing dismissed it  got=0
PASS hover: a moved pointer selects the row under it  got=0
PASS keys: Down x3 from the hovered row  got=3
PASS hover: the list scrolling under a resting pointer keeps the key selection  got=3
PASS hover: the pointer moving again selects  got=1
PASS tall: twelve rows  got=12
PASS tall: highlight on the last (current) row  got=11
PASS tall: the current row opened inside the viewport  got=true
PASS tall: the first row is scrolled out (the list is capped)  got=false
PASS tall: no reveal left pending  got=-1
PASS tall: Up to the first row brings it into view  got=[0,true]
PASS tall: a pending reveal runs on the row's next geometry change  got=[-1,true]
PROBE OK
ok   model picker: three rows, the current one marked, keys and a click report the id through picked; a current row past the fold opens in view; hover selects only on pointer movement
== test_ai_threads exit=0
PROBE OK
ok: 3 threads created, reloaded from disk and read back without crossing
== test_keybind_descriptions exit=0
keybind descriptions: all 149 binds described or hidden
== test_file_length exit=0
ok: 934 files under cap, 34 allow-listed and not grown
```
qmllint: 0 errors in the six files (the test's step). `ModelPicker.qml` is 282 lines; the other touched files are unchanged
since round 1. Live check for the lead after `koompi reload`: with a long Ollama list and the current model at the bottom, the
chip opens the sheet already scrolled to it; press Down a few times with the mouse resting over the list and the highlight does
not jump back.
