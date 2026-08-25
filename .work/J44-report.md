# J44 report: remote route key gate, extraModels, a real window for remote models

Branch `j44-remote-route-key-gate`. All five Do steps done; no Stop condition hit.

## Where things landed

- **The gate lives in `services/ai/KeyGate.qml`**, called once at the top of `Requester.makeRequest()` before anything is built. `requires_key` + keyring loaded + empty `apiKeys[key_id]` → no curl, one interface message (the existing `addApiKeyAdvice`), the user's turn stays; keyring not loaded → fetch, and the send re-enters `makeRequest` on `KeyringStorage.loadedChanged`. A keyring that never answers (locked → `try_lookup.sh` exit 2, `loaded` never flips) is reported after 10 s instead of hanging the turn.
- **No empty bearer**: both strategies now emit `${API_KEY:+-H "Authorization: Bearer ${API_KEY}"}`; bash drops the whole `-H` when the var is empty. `Requester.qml:145` got its `?.`.
- **`ai.extraModels`** is read by the new `services/ai/ExtraModels.qml` (mounted from ModelRegistry, one line). Entries land in `models` under their `model` id; malformed (no `model`/`endpoint`, or the id `remote`/`local`) → one `console.warn` naming the index (deduped across the config's reload-after-write-back); `policies.ai == 2` drops non-local endpoints and the remote slot. `AiModel` grew `contextWindow`.
- **Window**: `Conversation.contextWindow` is litert → entry's `context_window` → `modelWindows` → config → fallback `131072` hosted / `8192` local (`localhost`/`127.0.0.1`). `contextWindowSource` says which.
- Docs: `docs/agents/ai.md`.

## Two bugs found in the touched code, fixed in the same change

1. **`Conversation.compact()` never sent the key**: it called `buildAuthorizationHeader(envVar)` without the model, so `!model?.requires_key` returned `""` and the compactor hit remote endpoints with no `Authorization` at all. Now passes `model`.
2. **First turn on a fresh runtime dir ran an empty script.** `FileView.setText` is asynchronous; `Requester` starts bash right after it. Reproduced standalone: round 0 bash saw 0 bytes with the default, 5000 with `blockWrites: true`. Showed up in the probe as "assistant message appended, curl shim never ran". `Requester.scriptFile` and `Conversation.compactorScriptFile` are `blockWrites: true` now (the compactor's `watchChanges: false` line was the default and made room, Conversation stays 729).

## Acceptance 1: probe output (a)–(d) and the curl shim log

Gate run (`PROBE_MODE=gate`: no key in the fake keyring; curl shimmed to a log):

```
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
[AI] ai.extraModels[1] skipped: an entry needs a "model" id (not remote/local) and an "endpoint"
PASS Persistent ready  got=true
PASS remote slot model  got="stealth/ox-alpha"
PASS remote slot endpoint  got="https://tokenra.io/v1/chat/completions"
PASS remote slot api_format  got="openai"
PASS remote slot key_id  got="oxalpha"
PASS remote slot requires_key  got=true
PASS remote slot key_get_link  got="https://oxalpha.io/ox-alpha-api.html"
PASS remote slot logo  got="oxalpha-symbolic"
PASS current model id  got="remote"
PASS extra: in modelList  got=true
PASS extra: malformed entry not in modelList  got=false
PASS extra: remote slot still there  got=true
PASS extra: model  got="test/extra-1"
PASS extra: name  got="Probe Extra"
PASS extra: endpoint  got="https://example.test/v1/chat/completions"
PASS extra: api_format  got="openai"
PASS extra: key_id  got="extra"
PASS extra: requires_key  got=true
PASS extra: key_get_link  got="https://example.test/keys"
PASS extra: icon  got="spark-symbolic"
PASS extra: description  got="Probe | extra"
PASS extra: contextWindow  got=200000
PASS window: shipped contextWindow config is 0  got=0
PASS window: remote stealth/ox-alpha  got=131072
PASS window: remote source  got="fallback (hosted)"
PASS window: extra entry's context_window wins  got=200000
PASS window: LiteRT-served unknown name unchanged  got=8192
PASS window: LiteRT source  got="fallback (local)"
PASS window: local gemma keeps the model default  got=8192
PASS window: hosted gpt-4o keeps the model default  got=128000
AUTH_TEMPLATE openai ${API_KEY:+-H "Authorization: Bearer ${API_KEY}"}
AUTH_TEMPLATE mistral ${API_KEY:+-H "Authorization: Bearer ${API_KEY}"}
PASS gate: keyring not loaded before the first send  got=false
engine message: hello without a key
PASS gate: nothing running while the keyring loads  got=false
engine message: To set an API key, pass it with the /key command | To view the key, pass "get" with the command<br/> | ### For stealth/ox-alpha: | **Link**: https://oxalpha.io/ox-alpha-api.html | 
PASS gate: keyring loaded by the wait  got=true
PASS gate: still nothing running  got=false
PASS gate: user turn kept  got="user,interface"
PASS gate: one interface message  got=1
PASS gate: advice names /key  got=true
PASS gate: advice carries the key link  got=true
PROBE OK
--- curl shim log (gate): 0 bytes
ok   openai header: nothing with an empty key, '-H' 'Authorization: Bearer <key>' with one
ok   mistral header: nothing with an empty key, '-H' 'Authorization: Bearer <key>' with one
```

Retry run (`PROBE_MODE=retry`: same refusal, then `/key sk-test-fake` and a plain `retryRequest()`):

```
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
[AI] ai.extraModels[1] skipped: an entry needs a "model" id (not remote/local) and an "endpoint"
PASS Persistent ready  got=true
PASS remote slot model  got="stealth/ox-alpha"
PASS remote slot endpoint  got="https://tokenra.io/v1/chat/completions"
PASS remote slot api_format  got="openai"
PASS remote slot key_id  got="oxalpha"
PASS remote slot requires_key  got=true
PASS remote slot key_get_link  got="https://oxalpha.io/ox-alpha-api.html"
PASS remote slot logo  got="oxalpha-symbolic"
PASS current model id  got="remote"
AUTH_TEMPLATE openai ${API_KEY:+-H "Authorization: Bearer ${API_KEY}"}
AUTH_TEMPLATE mistral ${API_KEY:+-H "Authorization: Bearer ${API_KEY}"}
PASS gate: keyring not loaded before the first send  got=false
engine message: hello without a key
PASS gate: nothing running while the keyring loads  got=false
engine message: To set an API key, pass it with the /key command | To view the key, pass "get" with the command<br/> | ### For stealth/ox-alpha: | **Link**: https://oxalpha.io/ox-alpha-api.html | 
PASS gate: keyring loaded by the wait  got=true
PASS gate: still nothing running  got=false
PASS gate: user turn kept  got="user,interface"
PASS gate: one interface message  got=1
PASS gate: advice names /key  got=true
PASS gate: advice carries the key link  got=true
engine message: API key set for stealth/ox-alpha
PASS retry: key stored  got="sk-test-fake"
PASS retry: request went out  got="user,interface,interface,assistant"
PASS retry: request finished  got=false
PROBE OK
--- curl shim log (retry): --no-buffer --max-time 180 https://tokenra.io/v1/chat/completions -H Content-Type: application/json -H Authorization: Bearer sk-test-fake ...
ok   key gate: no key -> advice, user turn kept, no curl; /key + retry -> one curl with the bearer; extraModels load with their fields, a malformed entry warns; windows: hosted 131072, local 8192, entry's context_window wins
```

(the `PASS extra:` / `PASS window:` rows of the retry run are identical to the gate run's and are elided)

## Acceptance 2: suite tails and line counts

```
$ nice -n 19 ionice -c 3 tests/test_ai_remote_default.sh
ok   source: default is stealth/ox-alpha, no gemini fallback, icon file present, no key material
ok   source: both strategies wrap the bearer in ${KEY:+...}, the compactor passes the model, the send path goes through KeyGate
ok   remote default: stealth/ox-alpha infers tokenra/openai/oxalpha with its key link, regressions hold, a stored remoteModel survives, a missing one takes the default, /model with no argument keeps the state
ok   openai header: nothing with an empty key, '-H' 'Authorization: Bearer <key>' with one
ok   mistral header: nothing with an empty key, '-H' 'Authorization: Bearer <key>' with one
ok   key gate: no key -> advice, user turn kept, no curl; /key + retry -> one curl with the bearer; extraModels load with their fields, a malformed entry warns; windows: hosted 131072, local 8192, entry's context_window wins
$ nice -n 19 ionice -c 3 bash tests/test_ai_threads.sh   (file is mode 644 on main, so via bash)
PASS no thread holds another thread's messages  mixed=0
PROBE OK
ok: 3 threads created, reloaded from disk and read back without crossing
$ nice -n 19 ionice -c 3 tests/test_services_qml_bugs.sh
PASS M14 valid directory applied  /home/userx/.tmp/tmp.5gI449hE3L/out
PROBE OK
ok   services: cliphist queue, checkupdates exit codes, xkb variants, wallpaper dir validation, easyeffects readback, emoji sloppy search, latex argv and exit code
$ nice -n 19 ionice -c 3 tests/test_file_length.sh
ok: 933 files under cap, 34 allow-listed and not grown
```

`wc -l`, main → branch: ModelRegistry.qml 401 → 399, Conversation.qml 729 → 729, Config.qml 827 → 827 (test_text_size pins it exactly), Requester.qml 386 → 390 (cap 400). New: KeyGate.qml 62, ExtraModels.qml 86.

## Acceptance 3: qmllint

`/usr/lib/qt6/bin/qmllint -I <tmp with qs symlink> -I /usr/lib/qt6/qml` on KeyGate, ExtraModels, Requester, ModelRegistry, Conversation, OpenAiApiStrategy, MistralApiStrategy, AiModel, Config: rc=0, 0 `Error` lines each.

## Acceptance 4: diff stat and the schema section

```
 docs/agents/ai.md                                  |  73 [32m+++++++[m
 .../quickshell/koompi/modules/common/Config.qml    |  14 [32m+[m[31m-[m
 .../quickshell/koompi/services/ai/AiModel.qml      |   2 [32m+[m
 .../quickshell/koompi/services/ai/Conversation.qml |  28 [32m+[m[31m--[m
 .../quickshell/koompi/services/ai/ExtraModels.qml  |  84 [32m++++++++[m
 .../quickshell/koompi/services/ai/KeyGate.qml      |  62 [32m++++++[m
 .../koompi/services/ai/MistralApiStrategy.qml      |   4 [32m+[m[31m-[m
 .../koompi/services/ai/ModelRegistry.qml           |   6 [32m+[m[31m-[m
 .../koompi/services/ai/OpenAiApiStrategy.qml       |   4 [32m+[m[31m-[m
 .../quickshell/koompi/services/ai/Requester.qml    |  12 [32m+[m[31m-[m
 tests/test_ai_remote_default.sh                    | 213 [32m++++++++++++++++++++[m[31m-[m
 11 files changed, 461 insertions(+), 41 deletions(-)
```

Schema section of `docs/agents/ai.md`:

## `ai.extraModels`

`services/ai/ExtraModels.qml` reads `Config.options.ai.extraModels` and registers each entry in `ModelRegistry.models` under its `model` id, so `/model <id>`, `Ai.modelList` and the picker see it.
It runs at startup and again whenever the config or `policies.ai` changes; entries that vanished are dropped.

```json
{
  "model": "stealth/ox-alpha",
  "endpoint": "https://tokenra.io/v1/chat/completions",
  "name": "Custom: 0xAlpha",
  "api_format": "openai",
  "key_id": "oxalpha",
  "requires_key": true,
  "key_get_link": "https://oxalpha.io/ox-alpha-api.html",
  "icon": "oxalpha-symbolic",
  "description": "0xAlpha via tokenra",
  "homepage": "https://oxalpha.io/",
  "context_window": 131072
}
```

| key | required | default |
| --- | --- | --- |
| `model` | yes | the id `/model` takes; `/model` lowercases its argument, so keep it lowercase. `remote` and `local` are the slots and are refused |
| `endpoint` | yes | full chat-completions URL |
| `name` | no | `guessModelName(model)` |
| `api_format` | no | `openai`; also `gemini`, `mistral` |
| `key_id` | no | inferred from the name (`inferKeyIdForModel`); models sharing a key share an id |
| `requires_key` | no | `true` unless the endpoint is `localhost` / `127.0.0.1` |
| `key_get_link` | no | `""`; shown by the `/key` advice |
| `icon` | no | `guessModelLogo(model)` |
| `description` | no | `Custom \| <model>` |
| `homepage` | no | `""` |
| `context_window` | no | `0` (guess, see below); a positive integer pins the compaction budget |

An entry without `model` or `endpoint` is skipped with one `console.warn` naming its index.
With `policies.ai == 2` (local only) entries whose endpoint is not local are dropped, as the remote slot is.


## Notes for the lead

- `/model` lowercases its argument (`ModelRegistry.setModel`), so an extraModels id with capitals can never be selected by command; the doc and the Config.qml sample comment say to keep ids lowercase. Not changed: J45 owns the command text.
- The shipped sample entry duplicates the remote slot (`stealth/ox-alpha` as both `remote` and `stealth/ox-alpha`). That is what the config says; the picker will show both.
- `Conversation.qml` had no room, so two unrelated-looking rewrites made it: `currentModel` to one optional-chaining line and `modelDefaultWindow` to a `find`. Behaviour identical.
- `tests/test_ai_threads.sh` is not executable on main (mode 644); ran it via `bash`.
- No real endpoint was called: every curl in the tests goes to the shim and the log proves it.
