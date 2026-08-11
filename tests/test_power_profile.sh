#!/usr/bin/env bash
# The power profile is one setting with four places to change it: the quick toggle,
# the waffle icon, the settings page and the automatic swap on unplug. They used to
# read and write Quickshell's PowerProfiles singleton, which is a second client of
# power-profiles-daemon beside the one koompi-power already holds - and two clients
# means the toggle's write is invisible to the swap that has to undo it.
#
# So: nothing in the shell imports UPower any more, and the profile names are the
# daemon's own strings, which PROTOCOL.md is the contract for.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QML="$ROOT/dots/.config/quickshell/koompi"
SERVICE="$QML/services/PowerSaving.qml"
SHELLD="$ROOT/shell-services/shelld/src/services.rs"
PROTOCOL="$ROOT/shell-services/shelld/PROTOCOL.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$SERVICE" ]] || fail "no PowerSaving.qml"

# 1. One client of UPower and power-profiles-daemon on this seat, and it is not the shell.
hits="$(grep -rln 'Quickshell.Services.UPower' "$QML")"
[[ -n "$hits" ]] && fail "the shell imports UPower again, beside koompi-power: $hits"
hits="$(grep -rln 'PowerProfiles\.\|PowerProfile\.' "$QML")"
[[ -n "$hits" ]] && fail "Quickshell's PowerProfiles is back, so the shell has two writers: $hits"

# 2. Every profile write goes through the one function, so the AC profile the swap
#    restores is recorded whoever made the change.
grep -q 'function setProfile' "$SERVICE" \
    || fail "PowerSaving.setProfile is gone; each caller is writing the daemon itself"
for caller in modules/common/models/quickToggles/PowerProfilesToggle.qml \
    modules/settings/PowerConfig.qml; do
    grep -q 'PowerSaving.setProfile' "$QML/$caller" \
        || fail "$caller no longer writes the profile through PowerSaving.setProfile"
done

# 3. The strings the QML and the daemon have to agree on, in both directions.
grep -q '"set_profile"' "$SERVICE" \
    || fail "PowerSaving.qml no longer sends set_profile"
grep -q '"set_profile"' "$SHELLD" \
    || fail "koompi-shelld no longer answers set_profile"
grep -q 'profile: name' "$SERVICE" \
    || fail "the command no longer carries a \"profile\", which is the argument the daemon reads"
grep -q 'request.str("profile")' "$SHELLD" \
    || fail "koompi-shelld no longer reads \"profile\" as a string"

# 4. The three names the daemon knows. A rename on either side reads as a profile
#    the shell can never select and an icon that never resolves.
for name in power-saver balanced performance; do
    grep -rq "\"$name\"" "$QML/services/PowerSaving.qml" \
        "$QML/modules/common/models/quickToggles/PowerProfilesToggle.qml" \
        || fail "the shell no longer knows the profile \"$name\""
    grep -q "\`$name\`" "$PROTOCOL" \
        || fail "\"$name\" is not in PROTOCOL.md, which is what a consumer implements against"
done

# 5. Battery and profile both come off the one power subscription; without it the
#    daemon never opens UPower and every reading here stays at its default.
for consumer in services/Battery.qml services/PowerSaving.qml; do
    grep -q 'ShellServices.subscribe("power")' "$QML/$consumer" \
        || fail "$consumer never subscribes to power, so it binds to nothing"
done

echo "ok"
