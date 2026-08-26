# J44 — round 2 (lead's review of `a7739026`, rebased on main)

Fix these on your branch, same files you own; re-run the J44 gates and append a "Round 2" section to `.work/J44-report.md`.

1. `KeyGate.qml` imports `qs.services` and `QtQuick` only, but `:58` calls `Translation.tr` — the 10 s keyring timeout throws a
   ReferenceError and the user gets nothing. Import `qs.modules.common`; make the probe cover the timeout path (a keyring shim
   that never answers → the message appears).
2. `Conversation.compact()` (`:596-619`) builds curl without the gate: a missing key sends an unauthenticated compaction, the 401
   is applied as an empty summary and the turn is lost. Route it through the same admit check; when refused, skip compaction
   (leave `compacting` false, keep the conversation) and say so once.
3. `policies.ai == 2`: `ExtraModels.qml:20-22` treats `localhost` and `127.0.0.1` as local, `ModelRegistry.setModel` (`:306`)
   only `localhost`. One `isLocalEndpoint(url)` helper used by both (and by the remote slot's `requires_key`, `:72`); local means
   `localhost`, `127.0.0.1`, `::1`.
4. Extra-model ids: `/model` lowercases its argument, `ExtraModels` stores `entry.model` verbatim, so a capitalised id can never
   be selected and the fall-through clears `remoteEndpoint`/`remoteFormat`. Normalise the id with `toLowerCase()` at load and
   document that.
5. `ExtraModels.load()`: wrap each entry's creation in try/catch (a throw mid-load leaves `registry.models` pointing at destroyed
   objects); skip an entry whose id collides with a model that is not one of ours (`_added`) with a warn, instead of overwriting a
   discovered Ollama/LiteRT model that the next reload then deletes.
6. `requires_key`: treat anything other than a literal `false` as `true` (a string `"true"` or `1` currently disables the gate).
7. Context-window fallback: a self-hosted endpoint on the LAN (`192.168.x`, `10.x`, `172.16-31.x`, a bare hostname, `*.local`)
   is not "hosted"; give those the local `8192`, keep `131072` for everything else. Add a probe row for `http://192.168.1.5:8000/…`.
8. A deferred send should be dropped when the model changes or the chat is cleared while the keyring loads (`_deferred`
   invalidation); and the gate should wait for `keyringData` to be non-null, not only `loaded`, since `KeyringStorage` sets
   them from two different signals.

Accepted as is (no change): the single `_deferred` slot coalescing two sends into one request; the synchronous script write;
the `mkdir -p` race at startup.
