# searchd protocol

`searchd` speaks NDJSON on stdio: one JSON object per line, UTF-8, `\n` terminated,
flushed per line, in both directions. Same transport as `audiod`, `global-menu-daemon` and
`koompi-shelld` (`shelld/PROTOCOL.md`) - this document, not the Zig source, is what a
consumer implements against.

`protocol` is `1`.

A field marked optional may be absent or `null`; treat both the same. A reader must ignore
message types and object fields it does not know, so the protocol can grow without a version
bump.

## Which services are actually wired into the shell

The protocol carries three services - `files`, `clipboard`, `apps` - and the daemon answers
`search`/`update` for all three. **Only `files` is consumed by QML.** `SearchDaemon.qml`
routes `FileSearch`'s live disk search through this daemon; `Cliphist.qml` and `AppSearch.qml`
are untouched and keep calling `fuzzysort`/`Levendist` exactly as before.

This is a deliberate, evidence-based scope decision, not an oversight:

- `clipboard`/`apps` scoring here is a bounded smart-case substring match (see `query`
  below), not a port of `fuzzysort`/`Levendist`. It does not reproduce the real ranking,
  ordering, sloppy-mode behavior, or Unicode/Khmer normalization
  (`fuzzysort.js`'s `prepareLowerInfo` NFD-strips Latin diacritics; this does not) those two
  domains actually ship. Phase 1's own retain criterion is exact/codified behavior
  compatibility, which this does not meet, so it cannot replace `Cliphist.fuzzyQuery`/
  `AppSearch.fuzzyQuery` regardless of latency.
- Phase 1's pure-JS benchmark already found both domains sub-millisecond even at 10x
  today's scale (`.work/bench/search/scoring-{clipboard,apps}-default-stress-*.ndjson`);
  measuring the real protocol round trip confirmed it does not change the verdict - see
  `tests/bench/search/bench_daemon.js`'s output, `daemon-{clipboard,apps}-*.ndjson`.
- `files` is different in kind: its live search was never scored by `fuzzysort` in the
  first place. `FileSearch.qml`'s `fd`-backed disk search returns `fd`'s own raw output
  order with no re-scoring, so a bounded substring match is not a downgrade from what
  shipped - it is the same class of match `fd --fixed-strings` already performs, just
  against a persistent index instead of a fork+walk per keystroke.

The `Store` behind `clipboard`/`apps` stays in the daemon (tested, functional, harmless)
because it is a real capability worth keeping available and because rejecting an approach
does not mean deleting the code that measured it - but nothing in the shell calls it. Any
future attempt to wire it in has to close the behavior-compatibility gap first: either a real
`fuzzysort`-equivalent scorer in Zig with proven corpus parity (order, ties, Unicode/Khmer,
`sloppy` mode), or an explicit, separately-argued decision to accept an ordering change.

## Startup

1. `hello`, always first.
2. `state` for `files` (after its initial index walk completes - see `index-build`
   below), then `state` for `clipboard`, then `state` for `apps`, in that fixed order.

There is no `subscribe`/`unavailable` handshake the way `shelld` has one: `searchd` offers
every service it can build (currently: always all three) from the moment it starts, and a
service with nothing loaded yet (`clipboard`/`apps` before their first `update`) answers a
`search` with an honest empty result, not `unavailable` - the same posture `files` takes
toward a `$HOME` with nothing indexable in it.

### `hello`

| field | type | |
|---|---|---|
| `type` | string | `"hello"` |
| `protocol` | integer | `1` |
| `daemon` | string | `"searchd"` |
| `version` | string | daemon version |
| `services` | array of string | `["files", "clipboard", "apps"]` |

### `state`

| field | type | |
|---|---|---|
| `type` | string | `"state"` |
| `service` | string | |
| `ready` | boolean | always `true` here - see above |
| `entryCount` | integer | `files`: the index's current size. `clipboard`/`apps`: `0` at startup, then whatever the last `update` set |
| `buildMs` | number, `files` only | wall time the initial walk took, separate from any per-query cost |

## stdin commands

Each line is `{cmd, id?, ...}`. Every command line gets exactly one `reply`, including a
line that could not be parsed (`id: null` when the request carried none or was unreadable).
A blank line is ignored and draws no reply. A line over 8 MiB is `malformed` - larger than
`shelld`'s 256 KiB, because `update` pushes a whole clipboard/apps snapshot in one line
(measured close to 1 MiB for 7500 real-shaped clipboard entries).

| cmd | arguments | |
|---|---|---|
| `ping` | | replies `ok`. Touches nothing |
| `quit` | | replies `ok`, then exits `0`. Closing stdin is equivalent, without the reply |
| `search` | `id` (**required**), `service`, `query`, `limit?` | see below |
| `update` | `id`, `service` (`clipboard`\|`apps` only), `entries` | replaces that service's dataset wholesale |

### `search`

```json
{"cmd":"search","id":7,"service":"files","query":"invoice","limit":30}
```

`id` is required, unlike `shelld`'s optional one: the client (`SearchDaemon.qml`) discards a
reply whose `id` is older than the newest request it issued for that service (see
Staleness, below), which needs an `id` on every request to work at all. A `search` without
one is `bad_request`, not `malformed` - the line parsed fine, the business rule failed.

`limit` defaults to `30` (matching `FileSearch.qml`'s `fd --max-results 30`), clamped to
`1..200` rather than refused (the `brightness` service's precedent in `shelld/PROTOCOL.md`).

`files`: a `query` under 2 characters returns an empty result immediately, matching
`FileSearch.qml:71`'s own `search.length < 2` gate - `fd` is never invoked below that
either. `clipboard`/`apps` have no such floor (`Cliphist.fuzzyQuery`/`AppSearch.fuzzyQuery`
both run on a short or empty query too).

Reply:

```json
{"type":"reply","id":7,"ok":true,"service":"files","results":[{"path":"/home/u/Documents/invoice.pdf","name":"invoice.pdf"}],"total":3}
```

`results` items are `{path, name}` for `files` (field-identical to what
`LauncherSearch.qml`'s file mapper already consumes) and `{id, name}` for `clipboard`/`apps`
(`id` is the raw `<n>\t<preview>` clipboard line or the `.desktop` id - what a client
re-identifies the match by). `total` is the full match count before `limit` capped it, a
strict improvement over the current QML path, which tracks neither.

Error codes, the same closed set `shelld` uses: `malformed`, `unknown_command`,
`unknown_service`, `bad_request`, `rejected` (allocation failure only - nothing here is
ever "subscribed and currently down" the way `shelld`'s services can be, so `unavailable` as
a *reply* error never fires; the startup-level `unavailable` message, below, is a different
thing).

### `update`

```json
{"cmd":"update","id":3,"service":"clipboard","entries":[{"id":"1042\tinvoice draft","name":"invoice draft"}]}
```

Replaces `service`'s whole dataset - `entries` from a prior `update` are dropped, not
merged. `service` must be `clipboard` or `apps`; `files` builds its own index and answers
`bad_request` rather than silently ignoring an `update` aimed at it.

Every `entries` item needs a string `id` and a string `name`; anything else is
`bad_request` for the whole call (partial application is not attempted).

Reply: `{"type":"reply","id":3,"ok":true,"service":"clipboard","count":1}`.

## Staleness

The daemon always replies, in the order requests arrive, even to a request a newer one has
since superseded - ordering correctness lives client-side. `SearchDaemon.qml` keeps a
per-service `lastIssuedId`, stamped on every outgoing `search`; a reply whose `id` is less
than the current `lastIssuedId` for that service is discarded. Same shape as
`GlobalMenuService.qml`'s `generation` field (`if (payload.gen !== root.generation) return;`),
not a new pattern.

## `files`: index scope and ordering

The index is built once at startup by walking `$HOME` and kept live with `inotify` -
CREATE/DELETE/MOVED_FROM/MOVED_TO/DELETE_SELF, no polling, no periodic re-walk. Two
scoping decisions diverge from `FileSearch.qml`'s live `fd` invocation, both evidence-driven
and both documented in `src/index.zig`'s own doc comment:

1. **Non-hidden only** (`fd`'s own default; `FileSearch.qml` passes `--hidden` instead).
   Measured on this box: dotdirs (`.cargo`, `.rustup`, `.cache`, `.npm`, `.bun`, ...) were
   >95% of the file count under a `--hidden` walk and none of the searched content.
2. **`.gitignore`-aware**, matching `fd`'s own default (it respects `.gitignore` unless
   told `--no-ignore`, which `FileSearch.qml` does not pass). Support is a bounded subset:
   only patterns with no `/` are honored (the common case - `*.pyc`, `dist`,
   `__pycache__`), matched against the basename at any depth below the `.gitignore` that
   declared them, with a single `*` wildcard. Negation (`!pattern`) and slash-anchored
   patterns are parsed but skipped, which only ever under-excludes. Measured on a real
   `$HOME` with ~20 project checkouts: 222,141 files with no `.gitignore` awareness at all,
   143,497 with this bounded subset, 74,164 with `fd`'s own full implementation - the
   remaining gap is real and is the cost of the bounded subset, not a bug.

Matching is smart-case substring (`fd`'s own rule: any uppercase in the query makes it
case-sensitive), against the basename by default or the full root-relative path when the
query contains `/` (`FileSearch.qml:80`'s `--full-path` branch). Results are returned in
index order - the walk's own directory order, stable and deterministic, not re-sorted -
which is the explicit tie-break: a client wanting a different order applies one itself.

## Privacy

`clipboard` entries are clipboard content, held in RAM for exactly the reason
`Cliphist.entries` already holds them there. Nothing in `store.zig` or the code paths that
touch it writes that content to a log, a file, or a panic/`unreachable` path -
`tests/test_searchd.py` greps the clipboard-domain source for exactly that. The daemon's
only output channel for clipboard content is the `search` reply itself, the same channel
that already carries it today.
