#!/usr/bin/env bash
# The charge limit reads UPower through koompi-power and koompi-shelld. It used to
# fork busctl and index the four properties out of the output by line number, which
# is why this file once asserted their order; named fields on the wire retired that
# whole bug class. What is left still has no type checker behind it: the command
# name and the argument name are strings the QML and the daemon have to agree on,
# and UPower's own property names are an assumption the crate makes.
#
# Read-only: introspects UPower, never calls EnableChargeThreshold.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$ROOT/dots/.config/quickshell/koompi/services/ChargeLimit.qml"
PAGE="$ROOT/dots/.config/quickshell/koompi/modules/settings/PowerConfig.qml"
CRATE="$ROOT/shell-services/power/src/battery.rs"
SHELLD="$ROOT/shell-services/shelld/src/services.rs"
PROTOCOL="$ROOT/shell-services/shelld/PROTOCOL.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$QML" ]] || fail "no ChargeLimit.qml"

# 1. The QML no longer forks anything. A Process here means the port was reverted
#    for one caller and the daemon is being bypassed.
grep -qE '^[[:space:]]*Process[[:space:]]*\{|"busctl"' "$QML" \
    && fail "ChargeLimit.qml spawns a process again; koompi-power is what reads UPower now"

# 2. The one string the QML and the daemon must agree on, in both directions.
grep -q '"set_charge_threshold_enabled"' "$QML" \
    || fail "ChargeLimit.qml no longer sends set_charge_threshold_enabled"
grep -q '"set_charge_threshold_enabled"' "$SHELLD" \
    || fail "koompi-shelld no longer answers set_charge_threshold_enabled"
grep -q 'enabled: value' "$QML" \
    || fail "the command no longer carries a boolean \"enabled\", which is the argument the daemon reads"
grep -q 'request.bool("enabled")' "$SHELLD" \
    || fail "koompi-shelld no longer reads \"enabled\" as a boolean"

# 3. The document is the contract, so the command has to be in it.
[[ -f "$PROTOCOL" ]] || fail "no shelld/PROTOCOL.md"
grep -q 'set_charge_threshold_enabled' "$PROTOCOL" \
    || fail "set_charge_threshold_enabled is not in PROTOCOL.md, which is what a consumer implements against"

# 4. A machine that cannot do this must see nothing at all, not a dead switch.
grep -q 'visible: ChargeLimit.supported' "$PAGE" \
    || fail "the charge limit section is no longer hidden when unsupported"

# 5. Against the live daemon, if there is one. The object path is built from the
#    sysfs battery name, which is an assumption UPower could drop.
command -v busctl > /dev/null || { echo "ok (no busctl, static checks only)"; exit 0; }
bat=""
for d in /sys/class/power_supply/*; do
    [[ -r "$d/type" ]] || continue
    [[ "$(cat "$d/type")" == "Battery" ]] && { bat="$(basename "$d")"; break; }
done
[[ -n "$bat" ]] || { echo "ok (no battery, static checks only)"; exit 0; }

path="/org/freedesktop/UPower/devices/battery_$bat"
iface="$(busctl introspect org.freedesktop.UPower "$path" 2> /dev/null)" \
    || { echo "ok (UPower not answering, static checks only)"; exit 0; }

grep -q 'EnableChargeThreshold.*method.*b ' <<< "$iface" \
    || fail "UPower no longer offers EnableChargeThreshold(b) on $path"
for p in ChargeThresholdSupported ChargeThresholdEnabled ChargeStartThreshold ChargeEndThreshold; do
    grep -q "\.$p " <<< "$iface" || fail "UPower no longer exposes $p on $path"
    # the crate reads them by name, so a rename upstream lands here as well
    grep -q "\"$p\"" "$CRATE" || fail "koompi-power no longer reads $p"
done

echo "ok"
