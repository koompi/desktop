#!/usr/bin/env bash
# The charge limit talks to UPower through busctl, because Quickshell's UPower
# binding stops short of these properties. Nothing type-checks that argv, so a
# renamed property would silently show the limit as unsupported, or off while on.
#
# Read-only: introspects UPower, never calls EnableChargeThreshold.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$ROOT/dots/.config/quickshell/koompi/services/ChargeLimit.qml"
PAGE="$ROOT/dots/.config/quickshell/koompi/modules/settings/PowerConfig.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$QML" ]] || fail "no ChargeLimit.qml"

# 1. The four properties are read in one busctl call, and the four assignments
#    index that output by line. The order has to agree.
props="$(grep 'get-property' "$QML" | grep -o 'Charge[A-Za-z]*' | tr '\n' ' ')"
[[ "$props" == "ChargeThresholdSupported ChargeThresholdEnabled ChargeStartThreshold ChargeEndThreshold " ]] \
    || fail "unexpected get-property order: $props"

parsed="$(sed -n 's/.*root\.\([a-zA-Z]*\) = JSON\.parse(lines\[\([0-9]\)\])\.data.*/\2:\1/p' "$QML" | tr '\n' ' ')"
[[ "$parsed" == "0:supported 1:enabled 2:startThreshold 3:endThreshold " ]] \
    || fail "assignments no longer match the property order: $parsed"

# 2. A machine that cannot do this must see nothing at all, not a dead switch.
grep -q 'visible: ChargeLimit.supported' "$PAGE" \
    || fail "the charge limit section is no longer hidden when unsupported"

# 3. Writing goes through the one method, with the one signature UPower takes.
grep -q '"EnableChargeThreshold", "b"' "$QML" \
    || fail "EnableChargeThreshold is no longer called with a boolean"

# 4. Against the live daemon, if there is one. The object path is built from
#    the sysfs battery name, which is an assumption UPower could drop.
command -v busctl >/dev/null || { echo "ok (no busctl, static checks only)"; exit 0; }
bat=""
for d in /sys/class/power_supply/*; do
    [[ -r "$d/type" ]] || continue
    [[ "$(cat "$d/type")" == "Battery" ]] && { bat="$(basename "$d")"; break; }
done
[[ -n "$bat" ]] || { echo "ok (no battery, static checks only)"; exit 0; }

path="/org/freedesktop/UPower/devices/battery_$bat"
iface="$(busctl introspect org.freedesktop.UPower "$path" 2>/dev/null)" \
    || { echo "ok (UPower not answering, static checks only)"; exit 0; }

grep -q 'EnableChargeThreshold.*method.*b ' <<<"$iface" \
    || fail "UPower no longer offers EnableChargeThreshold(b) on $path"
for p in ChargeThresholdSupported ChargeThresholdEnabled ChargeStartThreshold ChargeEndThreshold; do
    grep -q "\.$p " <<<"$iface" || fail "UPower no longer exposes $p on $path"
done

echo "ok"
