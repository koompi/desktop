#!/usr/bin/env bash
# energy_full is the embedded controller's learned guess, not a measurement, and it
# wanders - so a decimal place reads as a healthy cell losing capacity every day.
# Whole percent only, with the cycle count beside it.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SERVICE="$ROOT/dots/.config/quickshell/koompi/services/Battery.qml"
POPUP="$ROOT/dots/.config/quickshell/koompi/modules/koompi/bar/BatteryPopup.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'Math.round(Battery.health)' "$POPUP" \
    || fail "battery health is no longer rendered as a whole percent"
grep -q 'Battery.health).toFixed' "$POPUP" \
    && fail "battery health is showing decimals again"

grep -q 'visible: Battery.cycleCount > 0' "$POPUP" \
    || fail "cycle count row is not gated on having a cycle count"

# Path comes off UPower's nativePath, so a machine whose battery is not BAT0
# still finds the file, and a machine with no battery gets an empty path.
grep -q 'power_supply/\${dev.nativePath}/cycle_count' "$SERVICE" \
    || fail "cycle count path is not derived from UPower nativePath"

# A battery without cycle_count must not log a warning every launch.
grep -q 'printErrors: false' "$SERVICE" \
    || fail "cycle count FileView is gone, or prints errors for a missing file"

echo "ok"
