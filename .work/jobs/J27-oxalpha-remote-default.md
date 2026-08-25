# J27 — 0xAlpha is the default remote model for the AI chat

Rithy, 2026-08-25: "for ai chat, remote we use 0xAlpha" — https://oxalpha.io/ox-alpha-api.html. The API is
OpenAI-compatible: `POST https://tokenra.io/v1/chat/completions`, `Authorization: Bearer <key>`, model id
`stealth/ox-alpha`, `stream: true` supported. Today `services/ai/ModelRegistry.qml:38-77` infers endpoint /
format / key slot from the model name, and a name with `/` is routed to OpenRouter with the `openrouter` key
slot, so 0xAlpha cannot be used without `/endpoint remote …` and it would share OpenRouter's key. The default
remote is `gemini-2.5-flash` (`modules/common/Persistent.qml:65`).

No API key goes into the repo, a test, a report, or a log. The key lives in the user's keyring only
(`/key` in the chat → `KeyringStorage`). The lead has a key for live verification; ask for it in your report's
stop section rather than reading it from anywhere.

## Files you own
- `dots/.config/quickshell/koompi/services/ai/ModelRegistry.qml`
- `dots/.config/quickshell/koompi/modules/common/Persistent.qml` (the `remoteModel` default only)
- `dots/.config/quickshell/koompi/modules/common/Config.qml` only if the `extraModels` sample should become the 0xAlpha sample (it should: replace the OpenRouter example, same shape)
- `dots/.config/quickshell/koompi/assets/icons/` one new symbolic icon if 0xAlpha has one worth shipping (optional)
- new `tests/test_ai_remote_default.sh`; `.work/J27-report.md`

## Do
1. `inferEndpointForModel` / `inferApiFormatForModel` / `inferKeyIdForModel`: `stealth/ox-alpha` (and any
   `stealth/` route) → `https://tokenra.io/v1/chat/completions`, `openai`, key id `oxalpha`. Put the rule before
   the generic `/` → OpenRouter rule. Add `key_get_link` for `oxalpha` wherever the other providers' links live
   (find where `addApiKeyAdvice` gets them) pointing at https://oxalpha.io/ox-alpha-api.html.
2. `Persistent.qml:65`: default `remoteModel` is `stealth/ox-alpha`. Read how `Persistent` migrates existing
   users (J11's defaults merge, `koompi-migrate`): a user who already picked another remote must keep it; say
   which mechanism guarantees that and prove it with the existing test for it, or with a probe.
3. `guessModelLogo` / `guessModelName`: give `stealth/ox-alpha` a name ("0xAlpha") and an icon that exists.
4. Test: a `qs -p` probe (pattern: `tests/test_services_qml_bugs.sh`) that instantiates ModelRegistry with a
   symlinked shell root and asserts, for `stealth/ox-alpha`: endpoint, api_format, key_id, requires_key true,
   and that `gemini-2.5-flash` and `deepseek/x` still infer what they did before (regression rows).
5. Live: with the lead's key entered through `/key` in the chat on this desktop (not by you; ask), one message
   to 0xAlpha and its reply pasted. If the account has no credit (the lead saw `insufficient_user_quota` at
   15:20), paste that error body as the demonstration that the request reached tokenra with the right
   headers, and say so.

## Acceptance
1. The probe output: every assertion line.
2. `grep -rn 'tokenra\|oxalpha' dots/ tests/` showing only code, docs and the test — no key material.
3. `./tests/run.sh` tail, baseline + 1.
4. The live exchange or the quota error body.

## Out of scope
- Any other provider, tool use, streaming changes, the memory/embedding provider.

## Stop conditions
- Never write the key anywhere but the keyring via the shell's own `/key`; never echo it in a command.
- If keeping an existing user's remote choice needs a change outside your files, stop and name it.
