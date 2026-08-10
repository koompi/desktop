# koompi-shelld protocol

`koompi-shelld` speaks NDJSON on stdio: one JSON object per line, UTF-8, `\n` terminated,
flushed per line, in both directions.
stdout carries state and events, stdin carries commands.
Same transport as `audiod`, `GlobalMenuService.qml:63` and `MemoryService.qml:155-187`.

This document, not the Rust source, is what a consumer implements against.

One daemon multiplexes every service in the `shell-services` workspace, so the shell holds
one `Process` and the system bus holds one connection.
Every message therefore carries a `service` alongside its `type`.

A field marked optional may be absent or `null`; treat both the same.
A reader must ignore message types, service names and object fields it does not know, so
the protocol can grow without a version bump.

`protocol` is `1`.

## Services

| service | crate | consumers |
|---|---|---|
| `hyprland` | `koompi-hyprland` | `HyprlandData.qml`, later `HyprlandKeybinds.qml` and `HyprlandXkb.qml` |
| `network` | `koompi-network` | `Network.qml` |
| `power` | `koompi-power` | `ChargeLimit.qml`, later `Battery.qml` and `PowerSaving.qml` |

The other seven crates get a `service` name here as each is wired up. A consumer that asks
for one that is not compiled in gets `unknown_service`, never silence.

## State is a snapshot, not a diff

Every service publishes over `tokio::sync::watch`, where last value wins and a consumer
that fell behind sees what is true now rather than a queue of states that are already
wrong. This protocol keeps that property: a change emits the **whole** `state` for that
service. There are no partial updates and no field-level events, because the crates keep
no shadow copy to diff against and inventing one would be inventing state.

Consecutive changes inside 100 ms coalesce into one `state`, so a wifi scan landing 30
access points does not write 30 lines. Override with `KOOMPI_SHELLD_DEBOUNCE_MS`.

Events that must not be dropped travel separately and are the reason
`tokio::sync::broadcast` exists in `koompi-service`. `network` and `power` have none.
The first will be `notifications`.

## Nothing runs until it is asked for

A service is inert until `subscribe` names it: no proxy, no bus match, no poll.
This is not only thrift. Opening power-profiles-daemon's interface activates the daemon,
which is why `PowerConfig::power_profiles` exists at `power/src/lib.rs:36-38`, and a shell
that never draws a wifi list should not be asking NetworkManager to scan.

`unsubscribe` tears the service back down. Subscribing to what is already subscribed
re-emits its `state` and is otherwise a no-op.

## Startup

1. `hello`, always the first line.
2. nothing at all until a `subscribe` arrives.

Per service named in a `subscribe`, in order: either a `state`, or an `unavailable`.
The `reply` to the `subscribe` comes after every one of them.

## Availability is per service and never fatal

`unavailable` reports one service that could not start or that lost its backing daemon.
The daemon stays up and every other service keeps running: no NetworkManager on a seat is
not a reason to lose the battery reading. This is `koompi_service::Error::Unavailable`,
which exists precisely because a seat with no battery and no NetworkManager is a working
seat and a consumer has to be able to draw that differently from a fault.

A service that goes unavailable while running is retried with the backoff in
`koompi_service::Backoff`, 250 ms doubling to 30 s. Recovery is announced by a `state`.
`koompi-shelld` exits only on `quit`, on stdin closing, or on a panic.

## stdout messages

### `hello`

| field | type | |
|---|---|---|
| `type` | string | `"hello"` |
| `protocol` | integer | `1` |
| `daemon` | string | `"koompi-shelld"` |
| `version` | string | daemon version |
| `services` | array of string | every service this build can offer |

### `state`

| field | type | |
|---|---|---|
| `type` | string | `"state"` |
| `service` | string | |
| `serial` | integer | per service, starts at 1, increases by 1 per snapshot |
| `state` | object | the service's state, below |

### `unavailable`

| field | type | |
|---|---|---|
| `type` | string | `"unavailable"` |
| `service` | string | |
| `reason` | string | `"no_bus"`, `"no_daemon"`, `"disconnected"`, `"refused"` |
| `message` | string | human readable. Not stable; do not match on it |

`no_daemon` is the backing service absent from the bus, `refused` is present but declining
to answer, `disconnected` is having lost one that was working.

### `reply`

One per command line, including a line that could not be parsed.

| field | type | |
|---|---|---|
| `type` | string | `"reply"` |
| `id` | integer, optional | the request's `id`, null when the request carried none or was unreadable |
| `ok` | boolean | |
| `error` | string | error code, only when `ok` is false |
| `message` | string | human readable, only when `ok` is false. Not stable; do not match on it |

`ok` on a write means the backing daemon accepted the call, not that the change has
landed. The result arrives as a `state`.

| code | |
|---|---|
| `malformed` | not JSON, not an object, no string `cmd`, or a line longer than 256 KiB |
| `unknown_command` | `cmd` is not one below. `message` is the command that was sent |
| `unknown_service` | no such `service`, or one this build does not carry |
| `not_subscribed` | the service is known but was never subscribed |
| `bad_request` | a required argument is missing, the wrong type, or out of range |
| `unavailable` | the service is subscribed and currently down |
| `unknown_access_point` | `network`: no access point at that path, usually a stale scan |
| `rejected` | the backing daemon refused the call |

## stdin commands

Each line is one object with a string `cmd`, an optional integer `id` echoed back in the
reply, and a `service` where the table says so.
A blank line is ignored and draws no reply.
Unknown extra fields are ignored.

| cmd | service | arguments | effect |
|---|---|---|---|
| `ping` | no | | replies `ok`. Touches nothing |
| `subscribe` | no | `services` array of string | starts each, emits its `state` or `unavailable`, then replies |
| `unsubscribe` | no | `services` array of string | stops each |
| `get_state` | yes | | re-emits that service's `state`, then replies. The `state` comes first |
| `set_poll_rate` | no | `factor` integer >= 1 | the shell-wide multiplier, offered to every subscribed service |
| `quit` | no | | replies `ok`, then exits `0` |

Closing stdin is equivalent to `quit` without the reply.

`set_poll_rate` is `koompi_service::PollRate`, the one factor `PowerSaving.qml:33` exports
to every other service's timers. `1` is normal, `2` is the save-on-battery rate. A factor
below 1 is clamped, not rejected. A service takes it only if it has a rate to take:
`network` applies it to the window it coalesces signals over, `hyprland` to the 30 ms it
waits before querying what an event invalidated, and `power` currently derives its own
from `save_on_battery` and ignores this. The reply is `ok` either way, because whether a
given service polls is not the caller's business.

### `hyprland` commands

None. Everything the shell writes to the compositor is a `dispatch`, which
`Quickshell.Hyprland` already owns; this service is the read side. Any `cmd` other than
`get_state` answers `unknown_command`.

### `network` commands

| cmd | arguments | maps to |
|---|---|---|
| `set_wireless_enabled` | `enabled` boolean | `Network.qml:58` `nmcli radio wifi on\|off` |
| `request_scan` | | `Network.qml:67` `nmcli dev wifi list --rescan yes` |
| `connect` | `path` string, `passphrase` string optional | `Network.qml:72` `nmcli dev wifi connect` |
| `disconnect` | | `Network.qml:80` `nmcli connection down` |

`connect` takes the `path` of an access point from the last `state`, not an SSID: two
networks can broadcast the same SSID and the path says which radio was picked. A path from
a scan that has since been replaced answers `unknown_access_point`.

`passphrase` is carried on the `connect` itself, which is what removes `Network.qml:88-98`
entirely. The QML wrote the passphrase into the saved profile with `nmcli connection
modify` and then retried the connection, so a wrong passphrase locked the user out of
their own network until they fixed the profile by hand. Here nothing is persisted until
NetworkManager has accepted it.

A `connect` that needs a passphrase and was given none, or was given a wrong one, fails
with `rejected`; the QML's cue for this was the string `Secrets were required` on nmcli's
stderr at `Network.qml:119`.

### `power` commands

| cmd | arguments | maps to |
|---|---|---|
| `set_charge_threshold_enabled` | `enabled` boolean | `ChargeLimit.qml:54` `busctl call ... EnableChargeThreshold` |
| `set_profile` | `profile` string | `PowerSaving.qml`, one of `power-saver`, `balanced`, `performance` |

## `network` state

| field | type | |
|---|---|---|
| `available` | boolean | NetworkManager answered |
| `version` | string | NetworkManager's own version |
| `state` | string | `unknown`, `asleep`, `disconnected`, `disconnecting`, `connecting`, `connected (local)`, `connected (site)`, `connected (global)` |
| `connectivity` | string | `unknown`, `none`, `portal`, `limited`, `full` |
| `wifi` | object | below |
| `wired` | array of wired device | below |
| `primary` | active connection, optional | the one carrying the default route |
| `active_connections` | array of active connection | |
| `ethernet` | boolean | derived: any wired device activated. `Network.qml:18` |
| `connected` | boolean | derived: `ethernet`, or wifi enabled and connected. `Network.qml:37` |
| `network_name` | string | derived: `primary.id`, else the first active connection, else `""`. `Network.qml:35` |
| `network_strength` | integer | derived: the associated AP's strength, else 0. `Network.qml:36` |
| `captive_portal` | boolean | derived: `connectivity` is `portal` |

The five derived fields are computed here rather than in JavaScript, which is the whole
point of `network/src/model.rs`. A consumer that recomputes them has reintroduced the bug
the crate's tests cover.

`captive_portal` is new. `Network.qml:84` opens `nmcheck.gnome.org` in a browser because
nmcli never told it whether there was a portal; NetworkManager knows.

### wifi object

| field | type | |
|---|---|---|
| `present` | boolean | a wireless radio exists on this seat |
| `enabled` | boolean | the manager's `WirelessEnabled`. `Network.qml:20` |
| `status` | string | `disabled`, `disconnected`, `connecting`, `connected`, `limited`. `Network.qml:33` |
| `scanning` | boolean | a scan this daemon asked for has not landed. `Network.qml:21` |
| `connecting` | boolean | `Network.qml:22` |
| `connect_target` | object, optional | `{ssid, ssid_hex}` of the SSID being brought up. `Network.qml:23` |
| `interface` | string | |
| `hw_address` | string | |
| `device_state` | string | the `DeviceState` words, `unknown` through `failed` |
| `bitrate` | integer | current link rate in kbit/s, 0 when not associated |
| `last_scan` | integer | `CLOCK_BOOTTIME` ms of the last completed scan, -1 if never |
| `networks` | array of access point | one entry per BSSID, every AP in range |
| `networks_by_ssid` | array of access point | one entry per SSID, the view `Network.qml:24` publishes |
| `active` | access point, optional | the associated AP. `Network.qml:25` |

`networks` and `networks_by_ssid` are both sent. The second is the dedupe at
`Network.qml:290-308`, associated beating strongest and strongest beating the rest, and
hidden SSIDs dropped. A consumer drawing a picker wants the second; one drawing a site
survey wants the first.

### access point object

| field | type | |
|---|---|---|
| `path` | string | NetworkManager object path, the handle `connect` takes |
| `ssid` | string | lossy UTF-8, for display only |
| `ssid_hex` | string | lowercase hex of the raw bytes, the identity |
| `ssid_valid_utf8` | boolean | false means `ssid` contains replacement characters |
| `strength` | integer | 0-100, nmcli's `SIGNAL` |
| `frequency` | integer | MHz, nmcli's `FREQ` |
| `band_ghz` | integer | 2, 5 or 6 |
| `hw_address` | string | the BSSID |
| `max_bitrate` | integer | kbit/s |
| `bandwidth` | integer | MHz, 0 when NetworkManager does not know |
| `security` | object | below |
| `last_seen` | integer | `CLOCK_BOOTTIME` seconds when last seen in a scan, -1 if never |
| `active` | boolean | the AP the device is associated with. nmcli's `ACTIVE` |

**An SSID is `ay` on the wire, not a string.** It is arbitrary bytes and is routinely not
UTF-8. `ssid_hex` is therefore the only safe key for comparison, dedupe or a map; `ssid`
is for drawing and nothing else. Going through nmcli's terse output lost these bytes
before the shell ever saw them, and `Network.qml:274-288` works around the loss with a
placeholder string and two regexes because a `:` inside an SSID collided with nmcli's own
field separator.

### security object

| field | type | |
|---|---|---|
| `label` | string | space separated tokens, what nmcli would have printed in `SECURITY` |
| `open` | boolean | no encryption at all |
| `wants_psk` | boolean | a passphrase will be asked for |
| `enterprise` | boolean | 802.1X, needs an identity rather than a passphrase |
| `wpa3` | boolean | |
| `owe` | boolean | opportunistic wireless encryption |

Derived from the `Flags` / `WpaFlags` / `RsnFlags` triple, so a consumer can ask whether a
network wants a passphrase before prompting for one. `Network.qml` only ever had the
label.

### wired device object

| field | type | |
|---|---|---|
| `interface` | string | |
| `state` | string | the `DeviceState` words |
| `connected` | boolean | state is `activated` |
| `carrier` | boolean | a cable in the socket |
| `speed` | integer | Mbit/s, 0 when the link is down |
| `hw_address` | string | |

`carrier` with `connected` false is a cable that is plugged in and was never brought up.
`Network.qml:198` infers ethernet from the word `connected` sitting next to the word
`ethernet` in nmcli's device table, and never sees carrier at all.

### active connection object

| field | type | |
|---|---|---|
| `path` | string | |
| `id` | string | the name `nmcli -t -f NAME c show --active` prints |
| `uuid` | string | |
| `kind` | string | `802-11-wireless`, `802-3-ethernet`, `bridge`, and so on |
| `state` | string | `unknown`, `activating`, `activated`, `deactivating`, `deactivated` |
| `default_route` | boolean | |
| `vpn` | boolean | |

## `power` state

| field | type | |
|---|---|---|
| `on_battery` | boolean | UPower's own, right at 100% on AC where `Battery.qml:15` cannot be |
| `plugged_in` | boolean | |
| `display` | battery, optional | UPower's aggregate device, the one `Battery.qml` binds to |
| `batteries` | array of battery | the real packs |
| `primary` | battery, optional | the first real pack, else `display` |
| `profiles` | object, optional | null when power-profiles-daemon is off or absent |

`ChargeLimit.qml` needs only `primary.threshold`. The rest is sent because `Battery.qml`
and `PowerSaving.qml` are the next two consumers and the crate reads it all in one pass
regardless.

### battery object

| field | type | |
|---|---|---|
| `native_path` | string | the sysfs name, `BAT0` and friends |
| `present` | boolean | |
| `state` | string | `unknown`, `charging`, `discharging`, `empty`, `fully-charged`, `pending-charge`, `pending-discharge` |
| `charging` | boolean | |
| `percentage` | number | 0-100, UPower's units. `Battery.qml:16` normalises to 0..1 itself |
| `low`, `critical`, `full` | boolean | against the `Config.options.battery` thresholds |
| `energy`, `energy_full`, `energy_full_design` | number | watt-hours |
| `energy_rate` | number | watts |
| `time_to_empty`, `time_to_full` | integer | seconds, 0 when unknown |
| `health` | number, optional | percent of design capacity |
| `cycle_count` | integer, optional | |
| `warning` | string | `unknown`, `none`, `discharging`, `low`, `critical`, `action` |
| `icon_name` | string | UPower's icon name |
| `threshold` | object | below |

### threshold object

| field | type | |
|---|---|---|
| `supported` | boolean | |
| `enabled` | boolean | |
| `start` | integer | percent to resume charging at |
| `end` | integer | percent to stop charging at |

`supported` false covers both a pack without the feature and a UPower below 1.90, which
has no such properties at all. That is the `lines.length < 4` branch at
`ChargeLimit.qml:64`, which cannot tell the two apart and does not need to.

### profiles object

| field | type | |
|---|---|---|
| `active` | string, optional | `power-saver`, `balanced` or `performance`; null if the daemon names one this build does not model |
| `available` | array of string | |
| `degraded` | string, optional | non-empty names the reason, usually `lap-detected` |

## `hyprland` state

| field | type | |
|---|---|---|
| `connected` | boolean | the compositor's socket is open and has answered |
| `windows` | array of client | `hyprctl clients -j`. `HyprlandData.qml:15` |
| `workspaces` | array of workspace | `hyprctl workspaces -j`, every one of them |
| `workspaces_numbered` | array of workspace | ids 1 to 100, the view `HyprlandData.qml:18` publishes |
| `active_workspace` | workspace, optional | `HyprlandData.qml:21` |
| `active_window` | client, optional | null when nothing is focused. `HyprlandData.qml:22` |
| `monitors` | array of monitor | `HyprlandData.qml:23` |
| `layers` | object | monitor name to `{levels: {level: [layer surface]}}`. `HyprlandData.qml:24` |

**The client, workspace, monitor and layer surface objects are Hyprland's own JSON, field
for field, `initialClass` and `monitorID` and `activeWorkspace` included.** This is the one
service whose objects are not renamed into this protocol's style, because every consumer
of them was reading `hyprctl -j` output directly and the port is meant to be invisible to
it. The compositor's schema is the schema; `hyprland/src/model.rs` is where it is written
down.

`workspaces` and `workspaces_numbered` are both sent, the way `network` sends both views
of the access point list. A lock screen parks a workspace at 2147483646 and a scratchpad
at a negative id; a bar drawing the numbered view wants neither, and something asking
which monitor a special workspace is on needs the full list.

The maps `HyprlandData.qml` publishes, window by address and workspace by id, are built in
the QML from these arrays rather than sent. They are the same objects under another key,
and sending them would put every client on the wire twice on every window event.

`get_state` is the whole command surface, and `active_window` being null is a real answer
rather than a gap: it is what the compositor reports with nothing focused.
