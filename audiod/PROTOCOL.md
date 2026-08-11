# audiod protocol

`audiod` speaks NDJSON on stdio: one JSON object per line, UTF-8, `\n` terminated,
flushed per line, in both directions.
stdout carries state and events, stdin carries commands.
This is the transport `GlobalMenuService.qml:63` and `MemoryService.qml:155-187` already
use.

This document, not the Zig source, is what a driver implements against.
`koompi-audio` (J05b) is held to it, the way `test_daemon.py` rather than either daemon
became the contract for the global menu.

Every message carries a `type`.
A field marked optional may be absent or `null`; treat both the same.
A reader must ignore message types and object fields it does not know, so the protocol can
grow without a version bump.

`protocol` is `1`.

## Volume scale

PipeWire stores a linear amplitude.
`wpctl`, `pavucontrol` and Quickshell's `PwNodeAudio.volume` all show its cube root.
This protocol uses the cube root everywhere, in both directions, so a `volume` here is the
number `wpctl` prints: `amplitude = volume ** 3`.

`1.0` is unattenuated. Values above `1.0` are amplification; `Audio.qml:18` caps the shell
at `2.00` and `set_volume` rejects anything higher.

## No polling

`audiod` is event driven end to end. It has no timer and no poll interval, so it has no
input from the shell-wide power-saving multiplier at `PowerSaving.qml:33`.
A driver that wants a rate limit imposes it on its own side.

## Startup

Lines arrive in a fixed order, so a driver can read them positionally:

1. `hello`, always the first line, emitted before any connection is attempted.
2. either `state` with `"ready": true`, or `unavailable` followed by exit.

After that the daemon streams events and answers commands in any order.
Nothing is emitted between `hello` and `state` except `unavailable`.

## stdout messages

### `hello`

| field | type | |
|---|---|---|
| `type` | string | `"hello"` |
| `protocol` | integer | protocol version, `1` |
| `daemon` | string | `"audiod"` |
| `version` | string | daemon version |
| `pipewire` | string | `pw_get_library_version()` of the linked library |

### `state`

A full snapshot. Emitted once at startup and again for every `get_state`.

| field | type | |
|---|---|---|
| `type` | string | `"state"` |
| `serial` | integer | snapshot counter, starts at 1, increases by 1 per snapshot |
| `ready` | boolean | true once the first registry roundtrip has settled |
| `default_sink` | string, optional | `node.name` of the default sink |
| `default_source` | string, optional | `node.name` of the default source |
| `output_devices` | array of node | `media.class` `Audio/Sink*` |
| `input_devices` | array of node | `media.class` `Audio/Source*` |
| `output_streams` | array of node | `media.class` `Stream/Output/Audio`, applications playing |
| `input_streams` | array of node | `media.class` `Stream/Input/Audio`, applications recording |

The four buckets are the four lists `Audio.qml:43-46` builds, and are disjoint.
Each is sorted by `id` ascending.
Non-audio nodes, video included, never appear.

### node object

| field | type | |
|---|---|---|
| `id` | integer | PipeWire global id, unique while the node exists, reused after |
| `serial` | integer, optional | `object.serial`, never reused within a session |
| `name` | string | `node.name` |
| `description` | string, optional | `node.description` |
| `nickname` | string, optional | `node.nick` |
| `application_name` | string, optional | `application.name`, normally set only on streams |
| `media_class` | string | raw `media.class` |
| `is_sink` | boolean | audio flows into this node |
| `is_stream` | boolean | an application stream rather than a device |
| `is_default` | boolean | `name` equals the matching default; always false for a stream |
| `ready` | boolean | volume and mute have been published |
| `volume` | number, optional | mean of `channel_volumes`; null until `ready` |
| `channel_volumes` | array of number | per channel, empty until `ready` |
| `mute` | boolean, optional | null until `ready` |

`is_default` is a snapshot taken when the enclosing message was written.
`defaults_changed` is the authoritative signal; recompute from `name` rather than caching
the flag.

### `node_added`, `node_changed`

`{"type": "node_added", "node": {...}}`

`node_added` fires once a node has a `name`, which can precede its volume, so the first
`node_added` may carry `"ready": false`.
`node_changed` fires when volume or mute changes, including the change that first makes
the node ready.
Neither fires before the initial `state`; nodes present at startup are in that snapshot
instead.

A `node_changed` is only emitted when a value actually differs, so writing a node's
current volume back to it produces no event.

### `node_removed`

| field | type | |
|---|---|---|
| `type` | string | `"node_removed"` |
| `id` | integer | the id that went away |

Only sent for a node that was announced, either in a `state` or by `node_added`.

### `defaults_changed`

| field | type | |
|---|---|---|
| `type` | string | `"defaults_changed"` |
| `default_sink` | string, optional | |
| `default_source` | string, optional | |

Read from the PipeWire `default` metadata object's `default.audio.sink` and
`default.audio.source`, not guessed from the node list.
That is the same source `Audio.qml:73-77` reaches through
`Pipewire.preferredDefaultAudioSink`.
Either name may be absent if no default is set, and may name a node that is not present.

### `reply`

One per command line, including a line that could not be parsed.

| field | type | |
|---|---|---|
| `type` | string | `"reply"` |
| `id` | integer, optional | the request's `id`, null when the request carried none or was unreadable |
| `ok` | boolean | |
| `error` | string | error code, only when `ok` is false |
| `message` | string | human readable, only when `ok` is false. Not stable; do not match on it |

`ok` on a write means PipeWire accepted the parameter, not that the value has landed.
The resulting value arrives as a `node_changed`.

Error codes:

| code | |
|---|---|
| `malformed` | not JSON, not an object, no string `cmd`, or a line past the 64 KiB input buffer |
| `unknown_command` | `cmd` is not one of the commands below. `message` is the command that was sent |
| `bad_request` | a required argument is missing, the wrong type, or out of range |
| `unknown_node` | no such node id, or no such device name |
| `not_ready` | the node exists but has not published its Props yet |
| `rejected` | PipeWire refused the parameter |

### `error`

Out of band, not tied to a command.

| field | type | |
|---|---|---|
| `type` | string | `"error"` |
| `error` | string | `"core"` for a PipeWire core error, `"out_of_memory"` for a snapshot that could not be built |
| `message` | string | |
| `res` | integer | negative errno, only for `"core"` |

### `unavailable`

Emitted once, then the process exits `1`. The daemon never blocks waiting for PipeWire.

| field | type | |
|---|---|---|
| `type` | string | `"unavailable"` |
| `reason` | string | see below |
| `message` | string | human readable |

| reason | |
|---|---|
| `connect_failed` | no PipeWire to connect to |
| `startup_timeout` | connected, but the first sync went unanswered within the startup budget |
| `loop_failed` | the loop thread would not start |
| `context_failed` | no PipeWire context |
| `registry_failed` | no registry |

The startup budget is 5000 ms, overridable with `AUDIOD_STARTUP_TIMEOUT_MS`.
Losing PipeWire while running is also `unavailable`, with reason `disconnected`.

## stdin commands

Each line is one object with a string `cmd` and an optional integer `id` echoed back in
the reply.
A blank line is ignored and draws no reply.
Unknown extra fields are ignored.

| cmd | arguments | effect |
|---|---|---|
| `ping` | | replies `ok`. Touches nothing |
| `get_state` | | emits a fresh `state`, then replies `ok`. The `state` comes first |
| `set_volume` | `node` integer, `volume` number in `[0, 2]` | sets every channel of the node to `volume` |
| `set_mute` | `node` integer, `mute` boolean | |
| `set_default_sink` | `name` string | |
| `set_default_source` | `name` string | |
| `quit` | | replies `ok`, then exits `0` |

Closing stdin is equivalent to `quit` without the reply.

`set_default_sink` and `set_default_source` write `default.configured.audio.sink` and
`default.configured.audio.source` on the `default` metadata object, which is the key
WirePlumber persists and the one `Pipewire.preferredDefaultAudioSink` sets.
`name` must be the `node.name` of a present device of the right direction, or the reply is
`unknown_node`.
The change is confirmed by the `defaults_changed` that follows.
