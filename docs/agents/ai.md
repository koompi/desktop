# The AI chat's remote route

For an agent editing `services/ai/`.
Three rules live there that are easy to undo by accident.

## The send gate

`services/ai/KeyGate.qml`, called from `Requester.makeRequest()` and from `Conversation.compact()` before any curl is built.
A model with `requires_key` goes out only when the keyring is ready (`loaded` and `keyringData` both set) and `apiKeys[key_id]` is non-empty.

- Key missing: no request.
  One interface message (the `/key` advice with the key link) is posted and the user's turn stays in the transcript, so `/key <key>` followed by a plain retry sends it.
- Keyring not loaded yet: that is "unknown", not "missing".
  The gate fetches the keyring and sends by itself once it reports loaded.
  A keyring that never answers (locked; `try_lookup.sh` exits 2) is reported after `keyringWaitMs` instead of leaving the turn hanging.
  A wait is dropped when the model changes or the chat is cleared meanwhile; the turn stays for a retry.
- Compaction refused for want of a key: nothing is sent, `compacting` stays false, the conversation is kept, and one note says so.

Belt and braces below the gate: `OpenAiApiStrategy` and `MistralApiStrategy` emit the header as bash's `${API_KEY:+-H "Authorization: Bearer ${API_KEY}"}`, so an empty key produces no `Authorization` header at all.
The compactor in `Conversation.compact()` goes through the same strategy call with the model, so it carries the key too.

`Requester.scriptFile` and `Conversation.compactorScriptFile` are `blockWrites: true`.
`FileView.setText` is asynchronous by default and bash was reaching an empty `request.sh` on a fresh runtime dir.

## `ai.extraModels`

`services/ai/ExtraModels.qml` reads `Config.options.ai.extraModels` and registers each entry in `ModelRegistry.models` under its `model` id, lower-cased, so `/model <id>`, `Ai.modelList` and the picker see it.
It runs at startup and again whenever the config or `policies.ai` changes; entries that vanished are dropped.
Only objects the loader created are taken back on a reload: an id a discovered Ollama or LiteRT model has taken since stays theirs, and the entry is skipped with a warning.

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
| `model` | yes | the id `/model` takes, stored lower-cased because `/model` lowercases its argument. `remote` and `local` are the slots and are refused |
| `endpoint` | yes | full chat-completions URL |
| `name` | no | `guessModelName(model)` |
| `api_format` | no | `openai`; also `gemini`, `mistral` |
| `key_id` | no | inferred from the name (`inferKeyIdForModel`); models sharing a key share an id |
| `requires_key` | no | absent: `true` unless the endpoint is local (`localhost`, `127.0.0.1`, `::1`); present: only a literal `false` turns the gate off, `"true"` or `1` count as `true` |
| `key_get_link` | no | `""`; shown by the `/key` advice |
| `icon` | no | `guessModelLogo(model)` |
| `description` | no | `Custom \| <model>` |
| `homepage` | no | `""` |
| `context_window` | no | `0` (guess, see below); a positive integer pins the compaction budget |

An entry without `model` or `endpoint`, or whose id is already taken, is skipped with one `console.warn` naming its index; an entry that throws while being created is skipped the same way and the others still load.
With `policies.ai == 2` (local only) entries whose endpoint is not local are dropped, as the remote slot is.
"Local" is one rule for the slot, the policy and the loader: `endpoints.js` `isLocal`, true for a host of `localhost`, `127.0.0.1` or `::1`.

## The context window

`Conversation.contextWindow`, first match wins:

1. LiteRT-LM's own `config.json` for a model served on the LiteRT port: the server rejects anything above it.
2. The `context_window` of an `extraModels` entry.
3. `Conversation.modelWindows`, a substring match on the model name (`gpt-4o`, `mistral`, `gemma`, ...).
4. `ai.memory.contextWindow` from the config when it is above 0.
5. The fallback: `8192` for a self-hosted endpoint (`endpoints.js` `isSelfHosted`: local, `10.x`, `192.168.x`, `172.16-31.x`, a bare hostname, `*.local`), `131072` for everything else.

Hosted models today are 128k and up.
An over-estimate delays compaction; an under-estimate throws context away, which is why the hosted fallback is the large number.
`contextWindowSource` names which rule fired and the meter shows it.
