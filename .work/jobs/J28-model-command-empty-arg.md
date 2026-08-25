# J28 — `/model` with no argument wipes the remote model state

Found by J08 (`.work/J08-report.md`, "Two things the lead should know first", 2): `ChatCommands.run` passes
`args[0]` (undefined → "") to `Ai.setModel`, and `services/ai/ModelRegistry.qml` `setModel("")` takes the
"unrecognised name is a remote model" branch: it sets `ai.model=remote`, `remoteModel=""` and clears
`remoteEndpoint` in `states.json`. Typing `/model` to see the current model destroys the user's remote choice.

## Files you own
- `dots/.config/quickshell/koompi/services/ai/ModelRegistry.qml` (`setModel` and whatever it calls for the empty case)
- `tests/test_ai_remote_default.sh` (add the case to the existing probe)
- `.work/J28-report.md`

## Do
1. Reproduce in the probe first (pattern already in `tests/test_ai_remote_default.sh`): start with
   `states.json` naming `deepseek-chat` and a `remoteEndpoint`, call `setModel("")` and `setModel("   ")`,
   show the state after.
2. Fix at the root in `setModel`: an empty or whitespace name changes nothing and answers with the current
   model and the usage line (`/model remote NAME`, `/model local:NAME`, `/model local`), through the same
   `engine.addMessage` path the other branches use. `ChatCommands.qml` is not yours and must not need a change.
3. Extend the probe: after the fix, both calls leave `ai.model`, `remoteModel`, `remoteEndpoint` untouched and
   the written `states.json` equals the one read.
4. `tests/test_file_length.sh` (ModelRegistry.qml is allow-listed at 403; it must not grow past that) and
   `./tests/run.sh` tail.

## Acceptance
1. Probe output before (state wiped) and after (state kept), pasted.
2. `./tests/run.sh` tail, unchanged count.

## Out of scope
- Any other command, the picker UI, `ChatCommands.qml`.

## Stop conditions
- Do not run `/model` on the live desktop; the probe is the demonstration.
