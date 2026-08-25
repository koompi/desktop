# J27 report — 0xAlpha is the default remote model for the AI chat

Branch `j27-oxalpha-remote-default` on top of `e9ed7bd0`.
Files touched: `services/ai/ModelRegistry.qml`, `modules/common/Persistent.qml` (the `remoteModel` default), `modules/common/Config.qml` (the `extraModels` sample), new `assets/icons/oxalpha-symbolic.svg`, new `tests/test_ai_remote_default.sh`, this report. Nothing else.
No API key was read, written, echoed or committed; the keyring was queried once for its key *ids* only (see Live).

## Do

1. **Inference.** The three functions were the same prefix ladder copied three times, so they are now one table `providers` (`[match, endpoint, api_format, key_id, key_get_link]`, first match wins) read by `inferProvider(modelName)`; `inferEndpointForModel` / `inferApiFormatForModel` / `inferKeyIdForModel` are one-line wrappers so `Ai.qml` and the probe keep their names. Row order is the old `if` order, with `/^stealth\//` → `https://tokenra.io/v1/chat/completions`, `openai`, `oxalpha`, `https://oxalpha.io/ox-alpha-api.html` placed ahead of the generic `/\//` → OpenRouter row. `key_get_link`: `addApiKeyAdvice` reads `model.key_get_link`, and the only place any link lived was the `extraModels` sample in `Config.qml`; the remote slot (`remoteModelObj`) never set one, so the advice printed an empty link for every provider. The link is now a table column and `remoteModelObj.key_get_link` binds to it. Only the 0xAlpha row has a link; the other providers had none before and, per Out of scope, still have none. `ModelRegistry.qml` went 403 → 390 lines, so the allow-list row shrinks as required.
2. **Default.** `Persistent.qml:65` `remoteModel: "stealth/ox-alpha"`; the two in-code fallbacks in `ModelRegistry.qml` (`remoteModelObj.model`, `setModel("remote")`) moved with it. The mechanism that keeps an existing user's choice is `Persistent`'s `JsonAdapter`: on load it assigns only the keys present in `states.json`, and every shell that ever ran wrote `ai.remoteModel` in full (`onAdapterUpdated → writeAdapter`), so an existing file always carries the user's current value and the QML default is never consulted for it. `koompi-migrate` / `libexec/update`'s three-way merge (`cmd_merge_config`, `tests/test_config_merge.sh`) is scoped to `~/.config/koompi/config.json` (`update:450`) and never reads `states.json`, so it cannot overwrite the choice either. The consequence, stated plainly: a user who never touched the picker keeps `gemini-2.5-flash` too, because their file says so; only a fresh install (no `states.json`) or a file missing the key gets 0xAlpha. Proof is the probe's three runs under Acceptance 1 (`kept` and `gap`), not an existing test: `test_config_merge.sh` covers `config.json`, nothing in the suite loaded `Persistent` from a prepared `states.json` before.
3. **Name and icon.** `guessModelName("stealth/ox-alpha")` → `0xAlpha` (shown by `ModelChip`), `guessModelLogo` → `oxalpha-symbolic`. The icon is new: `assets/icons/oxalpha-symbolic.svg`, a 16 px monochrome tracing of `https://oxalpha.io/favicon.svg` (ring, dot, chevron) in the same fill as the other symbolic icons. `AiModel.icon` is not rendered anywhere in the current UI (`grep` for `.icon` in `sidebarLeft/` finds nothing), so the icon is stored, not yet shown.
4. **Test.** `tests/test_ai_remote_default.sh`: static rows, then a `qs -p` probe from a symlinked shell root with `XDG_*` in a temp dir and `secret-tool` / `ollama` shimmed to exit 1, instantiating `ModelRegistry` against a stub engine. Run three times: no `states.json`, one naming `deepseek-chat`, one missing the key. Each run also checks the `states.json` the shell writes back. 85 assertion lines, 0 FAIL, ~6 s.
5. **Live.** Blocked on the key; see Stop.

## Acceptance

### 1. Probe output (every assertion line)

```
ok   source: default is stealth/ox-alpha, no gemini fallback, icon file present, no key material
--- states.json: (none)
PASS infer endpoint stealth/ox-alpha  got="https://tokenra.io/v1/chat/completions"
PASS infer api_format stealth/ox-alpha  got="openai"
PASS infer key_id stealth/ox-alpha  got="oxalpha"
PASS infer key_get_link stealth/ox-alpha  got="https://oxalpha.io/ox-alpha-api.html"
PASS infer key_id Stealth/OX-ALPHA (case)  got="oxalpha"
PASS name stealth/ox-alpha  got="0xAlpha"
PASS logo stealth/ox-alpha  got="oxalpha-symbolic"
PASS infer endpoint gemini-2.5-flash  got="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent"
PASS infer api_format gemini-2.5-flash  got="gemini"
PASS infer key_id gemini-2.5-flash  got="gemini"
PASS infer endpoint deepseek/x  got="https://openrouter.ai/api/v1/chat/completions"
PASS infer api_format deepseek/x  got="openai"
PASS infer key_id deepseek/x  got="openrouter"
PASS logo deepseek/x  got="openrouter-symbolic"
PASS infer endpoint deepseek-chat  got="https://api.deepseek.com/chat/completions"
PASS infer key_id deepseek-chat  got="deepseek"
PASS infer api_format mistral-large  got="mistral"
PASS infer key_id gpt-4.1  got="openai"
PASS infer endpoint unknown name  got="https://api.openai.com/v1/chat/completions"
PASS infer key_id unknown name  got="custom"
PASS name gemini-2.5-flash unchanged  got="Gemini 2.5 (Flash)"
PASS Persistent ready  got=true
PASS remote slot model  got="stealth/ox-alpha"
PASS remote slot endpoint  got="https://tokenra.io/v1/chat/completions"
PASS remote slot api_format  got="openai"
PASS remote slot key_id  got="oxalpha"
PASS remote slot requires_key  got=true
PASS remote slot key_get_link  got="https://oxalpha.io/ox-alpha-api.html"
PASS remote slot logo  got="oxalpha-symbolic"
PASS current model id  got="remote"
PROBE OK
--- states.json: {"ai":{"model":"remote","remoteModel":"deepseek-chat","remoteEndpoint":"","remoteFormat":""}}
PASS infer endpoint stealth/ox-alpha  got="https://tokenra.io/v1/chat/completions"
PASS infer api_format stealth/ox-alpha  got="openai"
PASS infer key_id stealth/ox-alpha  got="oxalpha"
PASS infer key_get_link stealth/ox-alpha  got="https://oxalpha.io/ox-alpha-api.html"
PASS infer key_id Stealth/OX-ALPHA (case)  got="oxalpha"
PASS name stealth/ox-alpha  got="0xAlpha"
PASS logo stealth/ox-alpha  got="oxalpha-symbolic"
PASS infer endpoint gemini-2.5-flash  got="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent"
PASS infer api_format gemini-2.5-flash  got="gemini"
PASS infer key_id gemini-2.5-flash  got="gemini"
PASS infer endpoint deepseek/x  got="https://openrouter.ai/api/v1/chat/completions"
PASS infer api_format deepseek/x  got="openai"
PASS infer key_id deepseek/x  got="openrouter"
PASS logo deepseek/x  got="openrouter-symbolic"
PASS infer endpoint deepseek-chat  got="https://api.deepseek.com/chat/completions"
PASS infer key_id deepseek-chat  got="deepseek"
PASS infer api_format mistral-large  got="mistral"
PASS infer key_id gpt-4.1  got="openai"
PASS infer endpoint unknown name  got="https://api.openai.com/v1/chat/completions"
PASS infer key_id unknown name  got="custom"
PASS name gemini-2.5-flash unchanged  got="Gemini 2.5 (Flash)"
PASS Persistent ready  got=true
PASS remote slot model  got="deepseek-chat"
PASS remote slot endpoint  got="https://api.deepseek.com/chat/completions"
PASS current model id  got="remote"
PROBE OK
--- states.json: {"ai":{"model":"remote","temperature":0.5}}
PASS infer endpoint stealth/ox-alpha  got="https://tokenra.io/v1/chat/completions"
PASS infer api_format stealth/ox-alpha  got="openai"
PASS infer key_id stealth/ox-alpha  got="oxalpha"
PASS infer key_get_link stealth/ox-alpha  got="https://oxalpha.io/ox-alpha-api.html"
PASS infer key_id Stealth/OX-ALPHA (case)  got="oxalpha"
PASS name stealth/ox-alpha  got="0xAlpha"
PASS logo stealth/ox-alpha  got="oxalpha-symbolic"
PASS infer endpoint gemini-2.5-flash  got="https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent"
PASS infer api_format gemini-2.5-flash  got="gemini"
PASS infer key_id gemini-2.5-flash  got="gemini"
PASS infer endpoint deepseek/x  got="https://openrouter.ai/api/v1/chat/completions"
PASS infer api_format deepseek/x  got="openai"
PASS infer key_id deepseek/x  got="openrouter"
PASS logo deepseek/x  got="openrouter-symbolic"
PASS infer endpoint deepseek-chat  got="https://api.deepseek.com/chat/completions"
PASS infer key_id deepseek-chat  got="deepseek"
PASS infer api_format mistral-large  got="mistral"
PASS infer key_id gpt-4.1  got="openai"
PASS infer endpoint unknown name  got="https://api.openai.com/v1/chat/completions"
PASS infer key_id unknown name  got="custom"
PASS name gemini-2.5-flash unchanged  got="Gemini 2.5 (Flash)"
PASS Persistent ready  got=true
PASS remote slot model  got="stealth/ox-alpha"
PASS remote slot endpoint  got="https://tokenra.io/v1/chat/completions"
PASS remote slot api_format  got="openai"
PASS remote slot key_id  got="oxalpha"
PASS remote slot requires_key  got=true
PASS remote slot key_get_link  got="https://oxalpha.io/ox-alpha-api.html"
PASS remote slot logo  got="oxalpha-symbolic"
PASS current model id  got="remote"
PROBE OK
ok   remote default: stealth/ox-alpha infers tokenra/openai/oxalpha with its key link, regressions hold, a stored remoteModel survives, a missing one takes the default
```

### 2. `grep -rn 'tokenra\|oxalpha' dots/ tests/`

22 lines: the provider row and logo rule in `ModelRegistry.qml`, the sample in `Config.qml`, the test. No key material.

```
dots/.config/quickshell/koompi/services/ai/ModelRegistry.qml:39:    // format, key id, key link]. stealth/ is 0xAlpha served by tokenra; any other
dots/.config/quickshell/koompi/services/ai/ModelRegistry.qml:42:        [/^stealth\//, "https://tokenra.io/v1/chat/completions", "openai", "oxalpha", "https://oxalpha.io/ox-alpha-api.html"],
dots/.config/quickshell/koompi/services/ai/ModelRegistry.qml:123:        if (m.startsWith("stealth/")) return "oxalpha-symbolic";
dots/.config/quickshell/koompi/modules/common/Config.qml:179:                        "description": "This is a custom model. Edit the config to add more! | Anyway, this is 0xAlpha via tokenra",
dots/.config/quickshell/koompi/modules/common/Config.qml:180:                        "endpoint": "https://tokenra.io/v1/chat/completions",
dots/.config/quickshell/koompi/modules/common/Config.qml:181:                        "homepage": "https://oxalpha.io/", // Not mandatory
dots/.config/quickshell/koompi/modules/common/Config.qml:182:                        "icon": "oxalpha-symbolic", // Not mandatory
dots/.config/quickshell/koompi/modules/common/Config.qml:183:                        "key_get_link": "https://oxalpha.io/ox-alpha-api.html", // Not mandatory
dots/.config/quickshell/koompi/modules/common/Config.qml:184:                        "key_id": "oxalpha",
tests/test_ai_remote_default.sh:2:# J27: 0xAlpha (stealth/ox-alpha via tokenra) is the default remote model and
tests/test_ai_remote_default.sh:17:OXALPHA_ENDPOINT="https://tokenra.io/v1/chat/completions"
tests/test_ai_remote_default.sh:25:[[ -f "$SHELL_ROOT/assets/icons/oxalpha-symbolic.svg" ]] \
tests/test_ai_remote_default.sh:26:    || fail "guessModelLogo names oxalpha-symbolic but assets/icons/oxalpha-symbolic.svg is missing"
tests/test_ai_remote_default.sh:74:        probe.check("infer endpoint stealth/ox-alpha", registry.inferEndpointForModel("stealth/ox-alpha"), "https://tokenra.io/v1/chat/completions");
tests/test_ai_remote_default.sh:76:        probe.check("infer key_id stealth/ox-alpha", registry.inferKeyIdForModel("stealth/ox-alpha"), "oxalpha");
tests/test_ai_remote_default.sh:77:        probe.check("infer key_get_link stealth/ox-alpha", registry.inferProvider("stealth/ox-alpha").key_get_link, "https://oxalpha.io/ox-alpha-api.html");
tests/test_ai_remote_default.sh:78:        probe.check("infer key_id Stealth/OX-ALPHA (case)", registry.inferKeyIdForModel("Stealth/OX-ALPHA"), "oxalpha");
tests/test_ai_remote_default.sh:80:        probe.check("logo stealth/ox-alpha", registry.guessModelLogo("stealth/ox-alpha"), "oxalpha-symbolic");
tests/test_ai_remote_default.sh:108:                probe.check("remote slot key_id", registry.remoteModelObj.key_id, "oxalpha");
tests/test_ai_remote_default.sh:110:                probe.check("remote slot key_get_link", registry.remoteModelObj.key_get_link, "https://oxalpha.io/ox-alpha-api.html");
tests/test_ai_remote_default.sh:111:                probe.check("remote slot logo", registry.remoteModelObj.icon, "oxalpha-symbolic");
tests/test_ai_remote_default.sh:149:echo "ok   remote default: stealth/ox-alpha infers tokenra/openai/oxalpha with its key link, regressions hold, a stored remoteModel survives, a missing one takes the default"
```

`git grep -nE 'sk-[A-Za-z0-9]{20,}|Bearer [A-Za-z0-9._-]{20,}'` over the branch: no hits. The test carries that grep as a static row.

### 3. `./tests/run.sh` tail

Baseline at `main`: 79 passed, 3 skipped, 0 failed. Now baseline + 1; `test_file_length.sh` passes with `ModelRegistry.qml` at 390 against its 403 row.

```
==> test_ai_remote_default.sh
  ok test_ai_remote_default.sh
...
==> test_file_length.sh
  ok test_file_length.sh
...
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

80 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
exit=0
```

### 4. Live exchange

Not done. Two things stand in the way, neither mine to move:

- The keyring on this desktop holds key ids `custom`, `gemini`, `openrouter` (`secret-tool lookup application koompi | python3 -c '…print(sorted(d["apiKeys"]))'`, ids only, values never printed). There is no `oxalpha` slot. If the 15:20 `insufficient_user_quota` came from this desktop, the key went in under `openrouter` through the old "/" rule.
- The running shell is the installed copy at `~/.config/quickshell/koompi`, whose `ModelRegistry.qml` is byte-identical to `main`'s, so even with a key in place a message from the chat today would go through the old code (OpenRouter route, `openrouter` slot), which demonstrates nothing about this branch. Getting the branch onto the desktop means installing it and reloading the shell on a session Rithy is using, which the brief reserves.

## Stop

Live verification needs, in this order, on this desktop:

1. Install this branch's shell tree and reload it: `./setup update` (or `koompi update --from-git` on this checkout), then the shell's own reload IPC. Not done by me: Rithy is on the session.
2. In the chat: `/model stealth/ox-alpha`, then `/key <the lead's tokenra key>` (lands under the `oxalpha` id in the keyring; nowhere else), then one message.
3. Paste the reply, or the `insufficient_user_quota` body if the account is still dry, into section 4 above.

Nothing outside my files was needed to keep an existing user's remote choice.
