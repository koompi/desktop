#!/usr/bin/env bash
# energy_full is the embedded controller's learned guess, not a measurement, and it
# wanders - so a decimal place reads as a healthy cell losing capacity every day.
# Whole percent only, with the cycle count beside it.
#
# The readings come off koompi-power through koompi-shelld now. Health and cycles are
# per-pack, so they have to be read from `primary` and not from the aggregate
# `display` device, which reports neither.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$ROOT/dots/.config/quickshell/koompi/services/Battery.qml"
POPUP="$ROOT/dots/.config/quickshell/koompi/modules/koompi/bar/BatteryPopup.qml"
CRATE="$ROOT/shell-services/power/src/battery.rs"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'Math.round(Battery.health)' "$POPUP" \
    || fail "battery health is no longer rendered as a whole percent"
grep -q 'Battery.health).toFixed' "$POPUP" \
    && fail "battery health is showing decimals again"

grep -q 'visible: Battery.cycleCount > 0' "$POPUP" \
    || fail "cycle count row is not gated on having a cycle count"

# The aggregate device has no Capacity and no cycle count, so reading either off
# `display` silently renders 0% health on every laptop.
grep -q 'ShellServices.power?.primary' "$SERVICE" \
    || fail "Battery.qml no longer reads the real pack; health and cycles come from primary"
grep -q 'root.pack?.health' "$SERVICE" \
    || fail "health is not read from the real pack"
grep -q 'root.pack?.cycle_count' "$SERVICE" \
    || fail "cycle count is not read from the real pack"

# The FileView this file used to carry is the crate's job now. A FileView or a
# Process here means the port was reverted for one reading.
grep -qE '^[[:space:]]*(FileView|Process)[[:space:]]*\{' "$SERVICE" \
    && fail "Battery.qml reads the seat itself again; koompi-power is what reads it now"

# sysfs first, because it is the only source on a UPower below 1.91.
grep -q 'power_supply/{native_path}/cycle_count' "$CRATE" \
    || fail "koompi-power no longer reads the sysfs cycle count"

echo "ok"
