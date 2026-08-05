#!/usr/bin/env bash
# A closed lid used to suspend the machine mid-job even with Keep awake on:
# logind weighs the lid against the handle-lid-switch class alone, and the
# toggle only blocked idle:sleep. Asserts the shipped Idle.qml holds all three,
# and that the pattern it reaps by still matches the process it starts.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
IDLE_QML="$REPO_ROOT/dots/.config/quickshell/koompi/services/Idle.qml"

fail() { printf '%s\n' "$1" >&2; exit 1; }

[[ -f "$IDLE_QML" ]] || fail "missing $IDLE_QML"

inhibit_line="$(grep -o 'systemd-inhibit [^"]*' "$IDLE_QML")"
[[ -n "$inhibit_line" ]] || fail 'Idle.qml no longer starts a systemd-inhibit'

what="$(sed -n 's/.*--what=\([^ ]*\).*/\1/p' <<< "$inhibit_line")"
for class in idle sleep handle-lid-switch; do
    grep -q "\(^\|:\)$class\(:\|$\)" <<< "$what" ||
        fail "the inhibitor drops '$class' (--what=$what), so that path still sleeps"
done

grep -q -- '--mode=block' <<< "$inhibit_line" ||
    fail "a delay-mode inhibitor only postpones sleep: $inhibit_line"

# The reaper runs before the next inhibitor starts. A pattern that stops matching
# leaks one live inhibitor per toggle-off, and the machine never sleeps again.
pattern="$(sed -n 's/.*inhibitorPattern: "\(.*\)".*/\1/p' "$IDLE_QML")"
[[ -n "$pattern" ]] || fail 'Idle.qml no longer declares inhibitorPattern'

# What pkill -f sees: the [q] class matches the real "q" on the running process.
cmdline="$(sed "s/'//g" <<< "$inhibit_line")"
grep -qE "$pattern" <<< "$cmdline" ||
    fail "inhibitorPattern '$pattern' does not match the command it reaps: $cmdline"

# ...and not the bash -c wrapper's own cmdline, which carries the pattern text.
grep -qE "$pattern" <<< "$pattern" &&
    fail "inhibitorPattern '$pattern' matches itself, so pkill kills the wrapper mid-start"

printf 'keep awake lid test passed\n'
