#!/usr/bin/env bash
# hyprlock's status.sh picked the battery with a *BAT* glob and then read
# status and capacity from whatever supply sorted first under
# /sys/class/power_supply: a mouse battery or a USB-PD source could answer for
# the laptop pack. Runs the script against a fake supply tree.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/dots/.config/hypr/hyprlock/status.sh"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

supply() {
    local name="$1" status="$2" capacity="$3"
    mkdir -p "$tmp/ps/$name"
    : > "$tmp/ps/$name/uevent"
    [[ -n "$status" ]] && printf '%s\n' "$status" > "$tmp/ps/$name/status"
    [[ -n "$capacity" ]] && printf '%s\n' "$capacity" > "$tmp/ps/$name/capacity"
    return 0
}

status_line() { POWER_SUPPLY_DIR="$tmp/ps" bash "$SCRIPT"; }

# A mouse that sorts before the pack, and a USB-PD source after it.
supply AAA-hidpp_battery_0 Discharging 5
supply BAT0 Charging 80
supply ucsi-source-psy-USBC000:001 'Not charging' ''
out="$(status_line)"
[[ "$out" == '(+) 80%' ]] || fail "charging pack beside other supplies: got '$out', want '(+) 80%'"

printf 'Discharging\n' > "$tmp/ps/BAT0/status"
printf '42\n' > "$tmp/ps/BAT0/capacity"
printf 'Charging\n' > "$tmp/ps/AAA-hidpp_battery_0/status"
out="$(status_line)"
[[ "$out" == '42% remaining' ]] || fail "discharging pack beside a charging mouse: got '$out', want '42% remaining'"

rm -rf "$tmp/ps/BAT0"
out="$(status_line)"
[[ -z "$out" ]] || fail "no battery: got '$out', want an empty line"

printf 'hyprlock battery test passed\n'
