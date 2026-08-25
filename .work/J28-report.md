# J28 report — `/model` with no argument no longer wipes the remote state

Branch `j28-model-command-empty-arg`, worktree only. Nothing was run on the live desktop; the probe in
`tests/test_ai_remote_default.sh` is the demonstration.

## What was wrong

`Ai.setModel(args[0])` reaches `ModelRegistry.setModel` with `undefined` when `/model` has no argument.
The old first lines turned that into `""`, no branch matched, and the fall-through "unrecognised name is a
remote model" branch stored `remoteModel=""`, `model="remote"` and cleared `remoteEndpoint` and
`remoteFormat`. A line of spaces was worse: it was not trimmed, so `remoteModel="   "` was stored.

## Fix

`dots/.config/quickshell/koompi/services/ai/ModelRegistry.qml`, `setModel`: the name is trimmed and lower-cased
once (`(modelId ?? "").trim().toLowerCase()`), and an empty result answers through `engine.addMessage` with the
current model's name and description plus the usage line
(`/model remote NAME`, `/model local:NAME`, `/model local`) and returns before any branch touches
`Persistent.states`. `feedback=false` (the startup call) stays silent. The dispatcher (`AiChat.qml`, there is no
`ChatCommands.qml` in the tree) is unchanged.

File length: 390 → 401 lines, allow-listed at 403.

## Probe

Fourth `run_probe` in `tests/test_ai_remote_default.sh` (`PROBE_EMPTY_ARG=1`): `states.json` names
`deepseek-chat` with a stored `remoteEndpoint`, the probe calls `setModel("")` then `setModel("   ")` after
Persistent is ready, checks the in-memory state, both replies, waits 500 ms for Persistent's 100 ms write timer,
and the shell side then checks every `ai` key from the input file against the `states.json` written back.

### Before the fix (state wiped)

```
--- states.json: {"ai":{"model":"remote","remoteModel":"deepseek-chat","remoteEndpoint":"https://example.test/v1/chat/completions","remoteFormat":""}}
PASS Persistent ready  got=true
PASS remote slot model  got="deepseek-chat"
PASS remote slot endpoint  got="https://example.test/v1/chat/completions"
PASS current model id  got="remote"
engine message: Remote model set to ****
engine message: Remote model set to **   **
PASS empty arg: ai.model kept  got="remote"
FAIL empty arg: remoteModel kept  got="   " want="deepseek-chat"
FAIL empty arg: remoteEndpoint kept  got="" want="https://example.test/v1/chat/completions"
PASS empty arg: remoteFormat kept  got=""
FAIL empty arg: remote slot endpoint kept  got="https://api.openai.com/v1/chat/completions" want="https://example.test/v1/chat/completions"
PASS empty arg: one reply per call  got=2
FAIL empty arg: reply 0 names the current model  got=false want=true
FAIL empty arg: reply 0 carries the usage line  got=false want=true
FAIL empty arg: reply 1 names the current model  got=false want=true
FAIL empty arg: reply 1 carries the usage line  got=false want=true
PROBE FAILED 7
FAIL: probe 'empty' did not pass
```

The run stops at that `fail`, so the written-file comparison is not reached in this state; the in-memory
values above are what Persistent's write timer flushes 100 ms later.

### After the fix (state kept)

```
--- states.json: {"ai":{"model":"remote","remoteModel":"deepseek-chat","remoteEndpoint":"https://example.test/v1/chat/completions","remoteFormat":""}}
engine message: Current model: **deepseek-chat** | Remote | deepseek-chat | Change with `/model remote NAME`, `/model local:NAME` or `/model local`
engine message: Current model: **deepseek-chat** | Remote | deepseek-chat | Change with `/model remote NAME`, `/model local:NAME` or `/model local`
PASS empty arg: ai.model kept  got="remote"
PASS empty arg: remoteModel kept  got="deepseek-chat"
PASS empty arg: remoteEndpoint kept  got="https://example.test/v1/chat/completions"
PASS empty arg: remoteFormat kept  got=""
PASS empty arg: remote slot endpoint kept  got="https://example.test/v1/chat/completions"
PASS empty arg: one reply per call  got=2
PASS empty arg: reply 0 names the current model  got=true
PASS empty arg: reply 0 carries the usage line  got=true
PASS empty arg: reply 1 names the current model  got=true
PASS empty arg: reply 1 carries the usage line  got=true
PROBE OK
ok   remote default: stealth/ox-alpha infers tokenra/openai/oxalpha with its key link, regressions hold, a stored remoteModel survives, a missing one takes the default, /model with no argument keeps the state
```

The written `states.json` carried `model`, `remoteModel`, `remoteEndpoint` and `remoteFormat` exactly as read
(the python comparison in `run_probe` exits non-zero and prints the differing keys otherwise).

## Gates

`tests/test_file_length.sh`:

```
ok: 901 files under cap, 35 allow-listed and not grown
```

`./tests/run.sh` tail (baseline at main: 80 passed, 3 skipped, 0 failed):

```

80 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

## Scope

Only `ModelRegistry.qml`, `tests/test_ai_remote_default.sh` and this report were changed. No API key was
written anywhere; the probe shims `secret-tool` and `ollama` and runs under a temp `XDG_*`.
