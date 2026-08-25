#!/usr/bin/env bash
# The branded idle layer (O32) is wired through three files that nothing else
# ties together: the module under modules/koompi/screensaver, the one loader
# line in KoompiFamily.qml, and the hypridle listener that is its only switch.
# Drop any one and the layer is silently gone. This checks each stays, that the
# listener fires before the lock so the lock replaces the layer rather than the
# other way round, and that the layer never writes the backlight: hypridle.conf
# says why a second brightness writer is a bug (the "No idle dim" note).
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$ROOT/dots/.config/quickshell/koompi"
MODULE="$SHELL_ROOT/modules/koompi/screensaver"
FAMILY="$SHELL_ROOT/panelFamilies/KoompiFamily.qml"
STATES="$SHELL_ROOT/GlobalStates.qml"
IDLE_CONF="$ROOT/dots/.config/hypr/hypridle.conf"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

[[ -d "$MODULE" ]] || { fail "missing $MODULE"; exit 1; }
mapfile -t qml_files < <(find "$MODULE" -name '*.qml' | sort)
(( ${#qml_files[@]} > 0 )) || { fail "no QML under $MODULE"; exit 1; }

# 1. The family loads it exactly once, and the state bool it toggles exists.
count="$(grep -c 'component: Screensaver {}' "$FAMILY")"
(( count == 1 )) || fail "KoompiFamily.qml loads Screensaver $count times, wanted 1"
grep -q '^import qs.modules.koompi.screensaver$' "$FAMILY" \
    || fail "KoompiFamily.qml does not import qs.modules.koompi.screensaver"
grep -q 'property bool screensaverOpen: false' "$STATES" \
    || fail "GlobalStates.qml has no screensaverOpen"

# 2. The IPC surface hypridle calls, and the lock hook: the lock replaces the
#    layer, so screenLocked turning on must close it.
grep -q 'target: "screensaver"' "$MODULE/Screensaver.qml" \
    || fail "Screensaver.qml has no IpcHandler target \"screensaver\""
for verb in open close toggle; do
    grep -qE "function $verb\(\): void" "$MODULE/Screensaver.qml" \
        || fail "Screensaver.qml IPC has no $verb()"
done
grep -q 'function onScreenLockedChanged' "$MODULE/Screensaver.qml" \
    || fail "Screensaver.qml does not watch screenLocked"

# 3. hypridle: the listener exists, before the lock listener, with a shorter
#    timeout, and both halves call the shell.
saver_line="$(grep -n 'ipc call screensaver open' "$IDLE_CONF" | head -1 | cut -d: -f1)"
lock_line="$(grep -n 'on-timeout = loginctl lock-session' "$IDLE_CONF" | head -1 | cut -d: -f1)"
[[ -n "$saver_line" ]] || fail "hypridle.conf has no screensaver open listener"
[[ -n "$lock_line" ]]  || fail "hypridle.conf has no lock listener"
if [[ -n "$saver_line" && -n "$lock_line" ]]; then
    (( saver_line < lock_line )) \
        || fail "the screensaver listener (line $saver_line) comes after the lock listener (line $lock_line)"
    saver_timeout="$(sed -n "1,${saver_line}p" "$IDLE_CONF" | grep -E '^\s*timeout\s*=' | tail -1 | sed -E 's/.*=\s*([0-9]+).*/\1/')"
    lock_timeout="$(sed -n "1,${lock_line}p" "$IDLE_CONF" | grep -E '^\s*timeout\s*=' | tail -1 | sed -E 's/.*=\s*([0-9]+).*/\1/')"
    [[ "$saver_timeout" =~ ^[0-9]+$ && "$lock_timeout" =~ ^[0-9]+$ ]] \
        || fail "could not read the timeouts (screensaver '$saver_timeout', lock '$lock_timeout')"
    (( saver_timeout < lock_timeout )) \
        || fail "screensaver timeout ${saver_timeout}s is not before the lock at ${lock_timeout}s"
    grep -q 'on-resume = qs -c koompi ipc call screensaver close' "$IDLE_CONF" \
        || fail "hypridle.conf does not close the screensaver on resume"
fi

# 4. No second backlight writer (hypridle.conf's "No idle dim" note).
if offenders="$(grep -nE 'brightnessctl|Brightness\b' "${qml_files[@]}")"; then
    fail "the screensaver touches brightness:
$offenders"
fi

# 5. The QML parses. /usr/bin/qmllint is Qt 5 and rejects pragma ComponentBehavior.
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    LINT="$(mktemp -d)"
    trap 'rm -rf "$LINT"' EXIT
    ln -s "$SHELL_ROOT" "$LINT/qs"
    for f in "${qml_files[@]}"; do
        out="$("$QMLLINT" -I "$LINT" -I /usr/lib/qt6/qml "$f" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects ${f#"$SHELL_ROOT/"}"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in ${f#"$SHELL_ROOT/"}"; }
    done
    (( failed )) || echo "ok   qmllint: ${#qml_files[@]} screensaver files parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

(( failed == 0 )) || exit 1
echo "ok   screensaver: loaded once, IPC open/close/toggle, closes on lock, hypridle listener at ${saver_timeout}s before the lock at ${lock_timeout}s, no brightness writer"
