#!/usr/bin/env bash
# Bluetooth reads and writes through koompi-bluetooth: org.bluez for the objects,
# /dev/rfkill for the unblock that BlueZ needs before a power-on will take. What is
# left without a type checker behind it is the command names, the argument names, and
# the field renames the port off Quickshell.Bluetooth forced on every consumer.
#
# Read-only: never powers a radio or starts a scan.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$ROOT/dots/.config/quickshell/koompi"
QML="$QS/services/BluetoothStatus.qml"
CLIENT="$QS/services/ShellServices.qml"
SHELLD="$ROOT/shell-services/shelld/src/services.rs"
PROTOCOL="$ROOT/shell-services/shelld/PROTOCOL.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$QML" ]] || fail "no BluetoothStatus.qml"

# 1. The fork the crate exists to remove, and the second BlueZ client it replaces.
#    A shell holding its own Quickshell.Bluetooth adapter is a second writer of the
#    same daemon, which is how the power toggle went invisible to the state that had
#    to follow it.
grep -qE '"rfkill"' "$QML" \
    && fail "BluetoothStatus.qml forks rfkill again; koompi-bluetooth writes /dev/rfkill directly"
if grep -rq "^import Quickshell.Bluetooth" "$QS"; then
    grep -rln "^import Quickshell.Bluetooth" "$QS" >&2
    fail "the files above still import Quickshell.Bluetooth; koompi-shelld is the shell's only BlueZ client"
fi

# 2. The strings the QML and the daemon have to agree on, in both directions.
for cmd in set_powered set_discovering connect disconnect pair forget; do
    grep -q "\"$cmd\"" "$SHELLD" \
        || fail "koompi-shelld no longer answers the bluetooth command $cmd"
    grep -q "$cmd" "$PROTOCOL" \
        || fail "$cmd is not in PROTOCOL.md, which is what a consumer implements against"
done
grep -q 'request.str("device")' "$SHELLD" \
    || fail "koompi-shelld no longer reads \"device\" as a string"
grep -q 'device: device.path' "$QML" \
    || fail "a device command no longer names the BlueZ object path; an address is not what the daemon indexes by"
grep -q 'ShellServices.subscribe("bluetooth")' "$QML" \
    || fail "BluetoothStatus.qml never subscribes, so the adapter reads as absent"
grep -q 'payload.service === "bluetooth"' "$CLIENT" \
    || fail "ShellServices drops the bluetooth state on the floor; every binding reads undefined"

# 3. The two field renames the wire forced. `name` is now absent where BlueZ never
#    learned one, so a consumer showing it draws "Unknown device" for a headset it
#    could have named; `alias` is the one that always has a value. And `battery` is a
#    percentage where Quickshell published a 0..1 fraction.
if grep -rn 'device?\.name\|device\.name ||' "$QS"/modules > /dev/null; then
    grep -rln 'device?\.name\|device\.name ||' "$QS"/modules >&2
    fail "the files above read a device's name; alias is the field that always has one"
fi
if grep -rn 'batteryAvailable\|battery \* 100' "$QS" > /dev/null; then
    grep -rln 'batteryAvailable\|battery \* 100' "$QS" >&2
    fail "the files above still treat battery as Quickshell's 0..1 fraction; the wire sends a percentage"
fi

# 4. `powered` is not `power_state`. A controller that refuses the mgmt command leaves
#    Powered true and PowerState off, which is what a wedged Intel adapter reads as, so
#    the field has to survive on the wire even though no consumer draws it yet.
grep -q 'power_state' "$ROOT/shell-services/shelld/src/wire.rs" \
    || fail "power_state is off the wire; a wedged controller then reads as a working one"

# 5. Against the live bus, if there is one.
command -v busctl > /dev/null || { echo "ok (no busctl, static checks only)"; exit 0; }
busctl --system status org.bluez > /dev/null 2>&1 \
    || { echo "ok (bluez not on the bus, static checks only)"; exit 0; }

objects="$(busctl --system call org.bluez / org.freedesktop.DBus.ObjectManager GetManagedObjects 2> /dev/null)" \
    || fail "org.bluez is on the bus but does not answer GetManagedObjects, which is the crate's only read"
grep -q 'org.bluez.Adapter1' <<< "$objects" || { echo "ok (no adapter on this seat)"; exit 0; }
grep -q 'PowerState' <<< "$objects" \
    || fail "this BlueZ publishes no Adapter1.PowerState; the daemon would report every adapter as unknown"

# The uaccess ACL is what lets the unblock be a write rather than a fork of a setuid
# helper. Without it every power-on silently fails again on a soft-blocked radio.
[[ -w /dev/rfkill ]] \
    || fail "/dev/rfkill is not writable by this seat; the rfkill unblock cannot run and BlueZ will fail a power-on silently"

echo "ok"
