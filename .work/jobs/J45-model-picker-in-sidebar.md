# J45 — Switch model inside the sidebar; `/key` and `/model` stop pointing at Settings

Rithy, 2026-08-25 19:40: "we should be able to switch model without opening a new window."
Facts (lead's fact sheet, verify before changing):
- Every model affordance in the chat leaves the sidebar: the composer chip `aiChat/ChatComposer.qml:326-332` and the status-bar
  name `aiChat/composer/ChatStatusBar.qml:158-172` call `settingsRequested()` → `AiChat.qml:49-53` → `SettingsPages.open` →
  `Quickshell.execDetached(["bash","-c","~/.local/bin/koompi-settings …"])` (`services/SettingsPages.qml:113-115`), a second
  `qs` process and window that `koompi-settings:26-28` kills and relaunches when already open.
- The no-key button (`ChatStatusBar.qml:275-279`, "Settings") opens the same window, and `modules/settings/AiConfig.qml` has no
  key field (its only mention is the tooltip at `:75`). `ChatCommands.qml:27-32` tells the user "`/key` lives in Settings > AI now".
- `/model <id>` (`ChatCommands.qml:312-322`) is the only in-sidebar switch; completion lists `Ai.modelList`
  (`aiChat/CommandCompletion.qml:17-21`). `/key` takes `args[0]` only (`:351`).
- `ModelChip.qml` under `modules/koompi/intelligence/` is display-only. There is no menu/dropdown widget under
  `modules/common/widgets/` except `PopupToolTip.qml`; `aiChat/composer/AttachMenu.qml` (121) is the closest in-sidebar popup.

## Files you own
- `dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/AiChat.qml`
- `dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/aiChat/ChatComposer.qml`, `ChatCommands.qml`, `ChatTranscript.qml`,
  `CommandCompletion.qml`, `composer/ChatStatusBar.qml`, `composer/AttachMenu.qml` (reference only unless you factor a shared base)
- new `dots/.config/quickshell/koompi/modules/koompi/sidebarLeft/aiChat/composer/ModelPicker.qml` (≤ 400)
- new `tests/test_ai_model_picker.sh`
- `docs/navigation.md` (one row for the picker, if the file lists sidebar controls)

## Do
1. **ModelPicker.qml**: an in-sidebar popup in the style of `AttachMenu.qml`, listing `Ai.modelList` (name, description, a
   check on the current one). Picking calls `Ai.setModel(id)` and closes; Escape and click-outside close; keyboard up/down/enter
   work. The component takes its list through a property (`models`) and reports through a signal (`picked(string id)`) so the
   test can drive it without the `Ai` singleton; the composer wires `picked` → `Ai.setModel`.
2. The composer chip and the status-bar model name open the picker; neither calls `settingsRequested()` any more; their tooltips
   drop "Change it in Settings > AI".
3. No-key state: the status-bar button reads "Set key" and puts `/key ` into the composer with focus (the key goes to the
   keyring via the existing command); the red "needs an API key" text stays. `settingsRequested` may remain for other callers.
4. `ChatCommands.qml`: `/key` takes the rest of the line trimmed (not `args[0]`), and its "moved to Settings" note goes;
   `/model` with no argument opens the picker, with an argument keeps `Ai.setModel(arg)`, its "moved" note goes too.
   `noteThatItMoved` is deleted if nothing else uses it.
5. `tests/test_ai_model_picker.sh`: static greps (chip and status-bar handlers no longer call `settingsRequested`; `/key` no
   longer uses `args[0]`; no "Settings > AI" string in the two files) plus a `qs -p` probe that loads `ModelPicker.qml` with three
   fake models, opens it, checks three rows and the current mark, emits a pick and asserts `picked` carried the id. Skip the probe
   with a "skip:" line when `qs` is absent (the static half still runs); add the test to the CI allow-list in
   `.github/workflows/tests.yml` with that reason (you may edit only that `allowed=` block; no apostrophes in the reason).

## Acceptance
1. Paste the probe output and the static-check lines.
2. `nice -n 19 ionice -c 3 tests/test_ai_model_picker.sh`, `tests/test_ai_threads.sh`, `tests/test_file_length.sh`,
   `tests/test_keybind_descriptions.sh`: tails pasted; every touched QML file ≤ 400 lines (`wc -l`).
3. qmllint on every touched QML file: 0 errors.
4. A headless screenshot is not required; describe in the report exactly what a user does to switch model in three clicks or fewer.

## Out of scope
- `services/ai/**` (J44 owns the registry, the key gate, `extraModels`); `modules/settings/**`; `koompi-settings`;
  `SettingsPages.qml`; any new keyring code.
- Editing the live shell: the picker is verified by the probe and by the lead after `koompi reload`, not by restarting `qs`.

## Stop conditions
- Never write a real API key anywhere. Never restart or kill the live `qs`; never modify `~/.config/koompi/config.json`.
- If the picker needs a list shape `Ai.modelList` does not provide (e.g. descriptions), take what `AiModel` has today and report
  the gap; do not reach into `services/ai/`.
