# J44 — Remote route: refuse to send without a key, read `extraModels`, a real window for remote models

Rithy, 2026-08-25 19:40: "why does 0xAlpha not require an API key? our AI chat is somewhat wrong for remote."
Facts (cited by the lead's fact sheet, verify each before changing it):
- `services/ai/ModelRegistry.qml:63-79` remote slot has `requires_key: true` for tokenra.io, but the send path never checks it:
  `services/ai/Requester.qml:135-141` puts `""` in the env var when the key is missing and `OpenAiApiStrategy.qml:92-95` +
  `Requester.qml:192-195` still send `Authorization: Bearer ` (empty). The only gate is `/compact` (ChatCommands.qml:90-93, not yours).
- `Requester.qml:141` reads `model.requires_key` with no `?.` (`:135` has it).
- `modules/common/Config.qml:176-189` ships `ai.extraModels` (sample: 0xAlpha with `key_id: "oxalpha"`); nothing reads it
  (`ModelRegistry.qml:155` comment only). The registry's `models` is only `remote` + `local` + discovered Ollama/LiteRT (`:91-93`).
- `services/ai/Conversation.qml:498-502`: a remote model not in `modelWindows` (`:480-485`, substring match `:491-492`) and with
  `ai.memory.contextWindow` 0 gets `8192`; compaction (`:515-525`) and the meter run on that made-up number.
- Key storage is the system keyring only (`services/KeyringStorage.qml:77-91`); `currentModelHasApiKey` (`ModelRegistry.qml:21-27`)
  is `false` while the keyring has not loaded, which is "unknown", not "missing".

## Files you own
- `dots/.config/quickshell/koompi/services/ai/Requester.qml` (386 — cap 400; new logic goes in a sibling file)
- `dots/.config/quickshell/koompi/services/ai/ModelRegistry.qml` (401, allow-listed: may not grow; a sibling file for the extraModels loader)
- `dots/.config/quickshell/koompi/services/ai/OpenAiApiStrategy.qml`, `MistralApiStrategy.qml`, `AiModel.qml`
- `dots/.config/quickshell/koompi/services/ai/Conversation.qml` (allow-listed 729: may not grow)
- new files under `dots/.config/quickshell/koompi/services/ai/` as needed (each ≤ 400)
- `dots/.config/quickshell/koompi/modules/common/Config.qml` (allow-listed 827: comment edits on the `extraModels` block only, no growth)
- `tests/test_ai_remote_default.sh`
- `docs/agents/ai.md` (new, short: the send gate, extraModels, the window rule)

## Do
1. **Key gate on the send path.** Before any curl is built, when `model.requires_key` and the keyring has loaded and
   `apiKeys[model.key_id]` is empty: do not send; add one interface-role message from the existing `addApiKeyAdvice` text
   (link + `/key` usage) and leave the user's message in the transcript so a plain retry after `/key` works. When the keyring has
   not loaded yet, fetch it and send once it reports loaded (a wait, not a refusal). Note in the report which file the gate lives in.
2. **Never an empty bearer.** `buildAuthorizationHeader` (OpenAI and Mistral strategies) emits no `Authorization` header when the
   key is empty; with step 1 this is belt-and-braces, keep it anyway. Fix the `?.` at `Requester.qml:141`.
3. **Read `ai.extraModels`.** Each entry (`model`, `name`, `endpoint`, `api_format`, `key_id`, `requires_key`, `key_get_link`,
   optional `icon`, `description`, `context_window`) becomes an `AiModel` in `ModelRegistry.models` under its `model` id, so
   `/model <id>` and `Ai.modelList` see it. Malformed entries (no `model` or no `endpoint`) are skipped with one `console.warn`
   naming the index. `policies.ai == 2` (local only) drops the ones whose endpoint is not local, same rule as the remote slot.
   Keep the Config.qml sample valid for this schema; document the schema in `docs/agents/ai.md`.
4. **Context window for remote models.** In `Conversation.qml`'s chain, a model that is not served by LiteRT, matches nothing in
   `modelWindows`, and has no configured window gets `131072`, not `8192` (hosted models today are 128k+; an over-estimate
   delays compaction, an under-estimate throws context away). An `extraModels` entry's `context_window` wins when set. Local
   stays as is. `stream_options` stays (OpenAI and OpenRouter accept it).
5. Tests: extend `tests/test_ai_remote_default.sh`'s qs probe (it already runs `ModelRegistry` headless) with: (a) a
   `requires_key` model with no key → `sendUserMessage` produces the advice message and spawns no curl (shim `curl` on PATH,
   assert the shim log is empty); (b) an `extraModels` entry in the probe's config appears in `modelList` with its fields; (c) a
   malformed entry is skipped and warned; (d) `contextWindow` is 131072 for `stealth/ox-alpha` with window 0 and unchanged for a
   LiteRT-served model. Static half: grep that neither strategy can emit `Bearer "` with an empty value.

## Acceptance
1. Paste the probe output of (a)-(d) and the curl shim log (empty for (a)).
2. `nice -n 19 ionice -c 3 tests/test_ai_remote_default.sh`, `tests/test_ai_threads.sh`, `tests/test_services_qml_bugs.sh`,
   `tests/test_file_length.sh`: paste the tails. ModelRegistry.qml, Conversation.qml, Config.qml are not longer than on main
   (`wc -l` before and after).
3. qmllint (`/usr/lib/qt6/bin/qmllint -I <dir with qs symlink> -I /usr/lib/qt6/qml`) on every QML file you touched: 0 errors.
4. `git diff main --stat` and the schema section of `docs/agents/ai.md`.

## Out of scope
- Anything under `modules/koompi/sidebarLeft/` (J45 owns the picker, the `/key` and `/model` command text, the status bar).
- `modules/settings/AiConfig.qml`; the system prompt content (`defaults/ai/prompts/`); `KeyringStorage.qml`.
- Calling tokenra.io or any remote endpoint for real; the 0xAlpha account has no credit, nothing would answer anyway.

## Stop conditions
- Never write a real API key anywhere (test, report, log, config). The probe uses `sk-test`-style fakes only.
- Do not modify `~/.config/koompi/config.json` or `~/.local/state/koompi/states.json`; do not restart or kill the live `qs`.
- If step 1's gate cannot be placed without growing Requester.qml past 400, stop and report the split you propose.
