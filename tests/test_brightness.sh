#!/usr/bin/env bash
# Brightness reads and writes both panels through koompi-brightness: logind
# SetBrightness for the internal one, which is why there is no udev rule to install,
# and ddcutil for external ones. What is left without a type checker behind it is the
# command name, the argument names, and three QML traps this port paid for once.
#
# Read-only: never moves a panel.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$ROOT/dots/.config/quickshell/koompi/services/Brightness.qml"
SHELLD="$ROOT/shell-services/shelld/src/services.rs"
PROTOCOL="$ROOT/shell-services/shelld/PROTOCOL.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$QML" ]] || fail "no Brightness.qml"

# 1. The two forks the crate exists to remove. The Process left in this file is the
#    anti-flashbang screen capture, which stays in the shell.
grep -qE '"brightnessctl"|"ddcutil"' "$QML" \
    && fail "Brightness.qml forks brightnessctl or ddcutil again; koompi-brightness owns both backends"

# 2. The strings the QML and the daemon have to agree on, in both directions.
grep -q '"set_brightness"' "$QML" \
    || fail "Brightness.qml no longer sends set_brightness"
grep -q '"set_brightness"' "$SHELLD" \
    || fail "koompi-shelld no longer answers set_brightness"
grep -q 'request.str("panel")' "$SHELLD" \
    || fail "koompi-shelld no longer reads \"panel\" as a string"
grep -q 'request.f64("value")' "$SHELLD" \
    || fail "koompi-shelld no longer reads \"value\" as a number"
grep -q 'panel: monitor.panel.id' "$QML" \
    || fail "the command no longer names the panel by its id; a connector is not what the daemon indexes by"
grep -q 'set_brightness' "$PROTOCOL" \
    || fail "set_brightness is not in PROTOCOL.md, which is what a consumer implements against"
grep -q 'ShellServices.subscribe("brightness")' "$QML" \
    || fail "Brightness.qml never subscribes, so every panel reads as absent"

# 3. Seeding from the daemon must not ramp and must not write. raw -> fraction -> raw is
#    lossy: 52363 of 174545 reads as 0.29999 and writes back as 29%, so a shell that
#    seeded itself through the animation walked the panel down a percent every launch.
grep -q 'monitor.seeding = true' "$QML" \
    || fail "the adopted value is no longer seeded without the ramp; every launch will dim the panel"
grep -q 'enabled: monitor.animateChanges && !monitor.seeding' "$QML" \
    || fail "the ramp is no longer suppressed while seeding"
grep -q 'monitor.panel.brightness === monitor.multipliedBrightness' "$QML" \
    || fail "a frame that came from the daemon is written back to it again"

# 4. The daemon's state, not the panel binding. Nothing observes that binding until
#    something reads it, so QML leaves it dirty and its change signal lands far too late
#    to seed from: the monitors sat at zero and the first key press jumped to 5%.
grep -q 'onBrightnessChanged' "$QML" \
    || fail "the monitor no longer follows ShellServices.brightness; onPanelChanged alone does not arrive"
grep -q 'Component.onCompleted: monitor.adopt()' "$QML" \
    || fail "a monitor created after the daemon's only snapshot never seeds itself"

# 5. Connections is a child of a QtObject here, which has no default property. Assigned
#    to one it works; declared bare it takes the whole singleton down silently.
grep -q 'property Connections .*: Connections' "$QML" \
    || fail "the Connections is not assigned to a property; QtObject has no default property to hold it"

# 6. Against the live panel, if there is one. The crate reads max_brightness where
#    brightnessctl used to.
internal=""
for d in /sys/class/backlight/*; do
    [[ -r "$d/max_brightness" ]] && { internal="$d"; break; }
done
[[ -n "$internal" ]] || { echo "ok (no backlight, static checks only)"; exit 0; }

[[ "$(cat "$internal/max_brightness")" -gt 0 ]] \
    || fail "$internal reports a max_brightness of 0, which no fraction can be taken against"

command -v busctl > /dev/null || { echo "ok (no busctl, static checks only)"; exit 0; }
iface="$(busctl introspect org.freedesktop.login1 /org/freedesktop/login1/session/auto 2> /dev/null)" \
    || { echo "ok (logind not answering, static checks only)"; exit 0; }
grep -q 'SetBrightness.*method.*ssu' <<< "$iface" \
    || fail "logind no longer offers SetBrightness(ssu), which is what removed the udev rule"

echo "ok"
