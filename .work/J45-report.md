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
