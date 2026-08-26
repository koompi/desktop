# J44 — round 3 (last; lead's review of the round-2 branch, now `16a827d7` on main)

1. `KeyGate.qml:64` drops the deferred send on every `currentModelIdChanged`. `Ai.currentModelId` forwards a `property var`
   binding over `root.models`, and a `var` property emits its change signal on every re-evaluation even when the value is the
   same; `models` is reassigned during startup (Ollama discovery `ModelRegistry.qml:156/182/218`, and `ExtraModels.load()` on
   the first config reload). Scenario: keyring locked at login, user sends, discovery lands → the turn is dropped with only a
   console.log. Fix: capture the model id in `admit`, and in the handler drop only when the id actually differs; on every drop
   post one interface message (the user must see why nothing answered). Probe: a deferred send survives a `models` reassignment
   with the same id, and is dropped with a visible message on a real switch.
2. The single `_deferred` slot is shared by `Requester.makeRequest` and `Conversation.compact`: a compaction that defers while a
   user send is already deferred overwrites the send silently. Rule: a deferred send is never overwritten by a compaction
   (the compaction is skipped, the send stays); a deferred compaction may be replaced by a send. Probe it.
3. `ExtraModels.qml:35`: when a discovered model has taken an id since, the object this loader created is neither destroyed nor
   carried into `_added` — destroy it.

Re-run the J44 gates, append "Round 3" to the report, commit, say DONE. Same rules as before.
