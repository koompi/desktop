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
| `power` | `koompi-power` | `ChargeLimit.qml`, `Battery.qml`, `PowerSaving.qml` |
| `brightness` | `koompi-brightness` | `Brightness.qml` |
| `bluetooth` | `koompi-bluetooth` | `BluetoothStatus.qml` |

The other five crates get a `service` name here as each is wired up. A consumer that asks
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

`set_poll_rate` is `koompi_service::PollRate`, the one factor `PowerSaving.qml:35` exports
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

### `brightness` commands

| cmd | arguments | maps to |
|---|---|---|
| `set_brightness` | `panel` string, `value` number | `Brightness.qml` `brightnessctl s N%` and `ddcutil setvcp 10` |

`panel` is the `id` from `state`, not the connector: two outputs can share a connector
name across cards, and a logind panel is named for its sysfs device rather than its
screen. An id no panel answers to is `unavailable`.

`value` is 0..1, the fraction the shell has always worked in, and is clamped rather than
refused. The raw value it lands on is the backend's business: whole-percent steps with a
floor of one raw unit for logind, the fraction scaled onto the reported max for DDC.
**No path writes 0.** A laptop with no external monitor cannot tell a dark panel from a
hang, which is why `Brightness.qml:164` sent the literal `1` instead of `0%`.

The crate carries a second write, `set_multiplier`, and it is deliberately not offered
here. The anti-flashbang factor is a screen capture the shell takes, so the shell already
holds the user's requested brightness to return to and sends the product it has always
computed. `value` is therefore what lands on the panel, not what the slider reads.

Writes are debounced per panel: 300 ms for DDC, which is slow and misbehaves under rapid
change, and nothing at all for logind. A `set_brightness` per animation frame is therefore
fine on the internal panel, and was not when it was a `brightnessctl` fork.

### `bluetooth` commands

| cmd | arguments | maps to |
|---|---|---|
| `set_powered` | `powered` boolean | `BluetoothStatus.qml:17-30` `rfkill unblock bluetooth` then `Adapter1.Powered` |
| `set_discovering` | `discovering` boolean | `Adapter1.StartDiscovery` / `StopDiscovery` |
| `connect` | `device` string | `Device1.Connect` |
| `disconnect` | `device` string | `Device1.Disconnect` |
| `pair` | `device` string | `Device1.Pair` |
| `cancel_pairing` | `device` string | `Device1.CancelPairing` |
| `set_trusted` | `device` string, `trusted` boolean | `Device1.Trusted` |
| `forget` | `device` string | `Adapter1.RemoveDevice`, the adapter taken from the device's own path |

`device` is the BlueZ object path from the last `state`, not an address. It is named
`device` rather than `network`'s `path` because a bluetooth command can address either an
adapter or a device, and only these name the second.

`set_powered` on the default adapter, which is the first one BlueZ lists. Powering on
clears the rfkill soft block first, because BlueZ answers a `Powered = true` on a
soft-blocked adapter with success and then does nothing - the bug that made
`BluetoothStatus.qml` fork `rfkill` before every power-on. That fork is now an 8-byte
write to `/dev/rfkill`, and it buys the one thing the fork never returned: a radio held
off by a hardware switch answers `unavailable` instead of silently failing.

Discovery is one command carrying the state to reach rather than a start/stop pair,
because every call site is a switch writing what it is now.

### `power` commands

| cmd | arguments | maps to |
|---|---|---|
| `set_charge_threshold_enabled` | `enabled` boolean | `ChargeLimit.qml:54` `busctl call ... EnableChargeThreshold` |
| `set_profile` | `profile` string | `PowerSaving.qml:47`, one of `power-saver`, `balanced`, `performance` |

`set_profile` is the shell's only writer of power-profiles-daemon. The quick toggle, the
waffle icon and the settings page all read `profiles.active` and write through
`PowerSaving.setProfile`, because a second client of the daemon makes the toggle's write
invisible to the automatic swap that has to undo it on AC.

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
| `on_battery` | boolean | UPower's own, right at 100% on AC where a charge state cannot be |
| `plugged_in` | boolean | |
| `display` | battery, optional | UPower's aggregate device, the one `Battery.qml:19` binds to. Null on a seat with no laptop battery, which is how `Battery.available` is answered |
| `batteries` | array of battery | the real packs |
| `primary` | battery, optional | the first real pack, else `display` |
| `profiles` | object, optional | null when power-profiles-daemon is off or absent |

`ChargeLimit.qml` needs only `primary.threshold`, `PowerSaving.qml` only `on_battery` and
`profiles`, `Battery.qml` most of the rest. The crate reads it all in one pass regardless,
so all three share the one subscription.

### battery object

| field | type | |
|---|---|---|
| `native_path` | string | the sysfs name, `BAT0` and friends |
| `present` | boolean | |
| `state` | string | `unknown`, `charging`, `discharging`, `empty`, `fully-charged`, `pending-charge`, `pending-discharge` |
| `charging` | boolean | |
| `percentage` | number | 0-100, UPower's units. `Battery.qml:28` normalises to 0..1 itself |
| `low`, `critical`, `full` | boolean | against this crate's `PowerConfig`, not the shell's. `Battery.qml` scores its own, because `Config.options.battery` is what the user edits and `suspend` has no counterpart here |
| `energy`, `energy_full`, `energy_full_design` | number | watt-hours |
| `energy_rate` | number | watts |
| `time_to_empty`, `time_to_full` | integer | seconds, 0 when unknown |
| `health` | number, optional | percent of design capacity. Per-pack: the aggregate `display` device reports neither this nor `cycle_count`, so `Battery.qml` reads both off `primary` |
| `cycle_count` | integer, optional | sysfs first, `ChargeCycles` after; absent rather than 0 |
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

## `brightness` state

| field | type | |
|---|---|---|
| `panels` | array of panel | empty on a seat with no backlight and no DDC monitor, which is a real answer rather than an outage |

### panel object

| field | type | |
|---|---|---|
| `id` | string | the sysfs device for a logind panel, the DRM connector for a DDC one. What a command names |
| `connector` | string, optional | `eDP-1`, `DP-1`. What `Quickshell.screens` calls the same output |
| `backend` | string | `logind` or `ddc` |
| `brightness` | number | 0..1, `raw / raw_max`. What every consumer binds to |
| `raw` | integer | the panel's own units |
| `raw_max` | integer | |
| `bus` | integer, optional | `/dev/i2c-N`, DDC panels only |

`connector` is optional because a backlight whose sysfs `device` link does not name a DRM
connector cannot be matched to a screen; it is still controllable by `id`.

A brightness key pressed outside the shell moves the panel too, so the state follows
sysfs through `POLLPRI` on `actual_brightness` rather than only the writes this daemon
made. Where that cannot be opened it falls back to a 2 s poll, and that is the only place
`set_poll_rate` would apply - the crate takes the rate once, at connect, and ignores it
after.

## `bluetooth` state

| field | type | |
|---|---|---|
| `available` | boolean | derived: any adapter at all. A seat with none is a working seat |
| `powered` | boolean | derived: the default adapter's `powered`. `BluetoothStatus.qml:31` |
| `discovering` | boolean | derived: the default adapter's `discovering` |
| `connected` | boolean | derived: any device connected, on any adapter. `BluetoothStatus.qml:34` |
| `connected_count` | integer | derived, for the `+2` a toggle draws beside the first device's name |
| `adapter` | adapter, optional | the default one, the first BlueZ lists. Null on a seat with none |
| `adapters` | array of adapter | |
| `devices` | array of device | every device on every adapter, paired or merely seen |
| `rfkill` | object | below |

Ordering the device list is presentation and stays with the consumer; the fields to order
by are all here.

### adapter object

| field | type | |
|---|---|---|
| `path` | string | `/org/bluez/hci0` |
| `id` | string | `hci0`, the name `rfkill list` and `bluetoothctl` print |
| `address` | string | |
| `name` | string | |
| `alias` | string | the writable one, what the seat calls itself to other devices |
| `powered` | boolean | |
| `power_state` | string | `on`, `off`, `off-enabling`, `on-disabling`, `off-blocked`, `unknown` |
| `discoverable` | boolean | |
| `discovering` | boolean | |
| `pairable` | boolean | |

`power_state` is `Adapter1.PowerState`, and `powered` alone cannot stand in for it: a
controller that refuses the mgmt command leaves `powered` true and this at `off`, which is
exactly how a wedged Intel controller reads. `off-blocked` is the rfkill case arriving
from BlueZ's side rather than the kernel's.

### device object

| field | type | |
|---|---|---|
| `path` | string | what a command names |
| `adapter` | string | the adapter's object path, so a consumer can group without re-reading it |
| `address` | string | |
| `name` | string, optional | absent where BlueZ never learned one |
| `alias` | string | always set, falling back to the address with dashes |
| `paired` | boolean | |
| `trusted` | boolean | |
| `connected` | boolean | |
| `blocked` | boolean | |
| `icon` | string, optional | the freedesktop name, `audio-headset`, `input-keyboard` |
| `rssi` | integer, optional | dBm, only while the device is in range of a scan |
| `battery` | integer, optional | `org.bluez.Battery1.Percentage`, 0..100 |

`name` and `alias` are both sent because a consumer needs to show one and test the other:
`BluetoothStatus.qml:38` sorts MAC-shaped names last, and that shape is what `alias` falls
back to precisely when `name` is absent.

`battery` is a percentage. `Quickshell.Bluetooth` published a 0..1 fraction that every
consumer multiplied back up by 100.

### rfkill object

| field | type | |
|---|---|---|
| `soft_blocked` | boolean | any bluetooth switch soft-blocking. Clearable in software |
| `hard_blocked` | boolean | any bluetooth switch hard-blocking. A physical kill switch |
| `entries` | array of rfkill entry | every switch, of every kind |

### rfkill entry object

| field | type | |
|---|---|---|
| `index` | integer | `/sys/class/rfkill/rfkillN` |
| `kind` | string | `all`, `wlan`, `bluetooth`, `uwb`, `wimax`, `wwan`, `gps`, `fm`, `nfc`, `other` |
| `name` | string, optional | `tpacpi_bluetooth_sw`, `hci0`, `phy0`. From sysfs, absent if the switch vanished |
| `soft_blocked` | boolean | |
| `hard_blocked` | boolean | |

The wifi switches are in `entries` too, because the kernel replays every switch when
`/dev/rfkill` is opened and dropping the ones this service does not act on would be
inventing a filter. `soft_blocked` and `hard_blocked` at the top are the bluetooth ones
only, which is the same type-wide test `rfkill unblock bluetooth` makes.

A seat where `/dev/rfkill` cannot be opened publishes an empty `entries` and both flags
false. That is a bluetooth toggle that cannot be trusted rather than a service that failed
to start, so it is a `state` and not an `unavailable`.

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
