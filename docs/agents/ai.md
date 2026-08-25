# The AI chat's remote route

For an agent editing `services/ai/`.
Three rules live there that are easy to undo by accident.

## The send gate

`services/ai/KeyGate.qml`, called from `Requester.makeRequest()` before any curl is built.
A model with `requires_key` goes out only when the keyring has loaded and `apiKeys[key_id]` is non-empty.

- Key missing: no request.
  One interface message (the `/key` advice with the key link) is posted and the user's turn stays in the transcript, so `/key <key>` followed by a plain retry sends it.
- Keyring not loaded yet: that is "unknown", not "missing".
  The gate fetches the keyring and sends by itself once it reports loaded.
  A keyring that never answers (locked; `try_lookup.sh` exits 2) is reported after `keyringWaitMs` instead of leaving the turn hanging.

Belt and braces below the gate: `OpenAiApiStrategy` and `MistralApiStrategy` emit the header as bash's `${API_KEY:+-H "Authorization: Bearer ${API_KEY}"}`, so an empty key produces no `Authorization` header at all.
The compactor in `Conversation.compact()` goes through the same strategy call with the model, so it carries the key too.

`Requester.scriptFile` and `Conversation.compactorScriptFile` are `blockWrites: true`.
`FileView.setText` is asynchronous by default and bash was reaching an empty `request.sh` on a fresh runtime dir.

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

## The context window

`Conversation.contextWindow`, first match wins:

1. LiteRT-LM's own `config.json` for a model served on the LiteRT port: the server rejects anything above it.
2. The `context_window` of an `extraModels` entry.
3. `Conversation.modelWindows`, a substring match on the model name (`gpt-4o`, `mistral`, `gemma`, ...).
4. `ai.memory.contextWindow` from the config when it is above 0.
5. The fallback: `131072` for a hosted endpoint, `8192` for a local one.

Hosted models today are 128k and up.
An over-estimate delays compaction; an under-estimate throws context away, which is why the hosted fallback is the large number.
`contextWindowSource` names which rule fired and the meter shows it.
