#!/usr/bin/env bash
# Logging out has to end the calling session and nothing else.
#
# `pkill -i Hyprland` matches every compositor the user owns, so a shell left
# over from an earlier session takes down the live one, and killing only the
# compositor leaves the rest of the session in a scope logind waits on forever
# (KillUserProcesses=no). Both wlogout and the shell had that shape.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="$ROOT/dots/.config/quickshell/koompi/modules/common/functions/Session.qml"
WLOGOUT="$ROOT/dots/.config/wlogout/layout"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for f in "$SESSION" "$WLOGOUT"; do
    # Comments here explain the old pkill on purpose, so only look at code.
    sed 's|//.*||' "$f" | grep -qE 'pkill[^"]*[Hh]yprland' \
        && fail "$(basename "$f") logs out with an unscoped pkill again"
    grep -q 'terminate-session' "$f" \
        || fail "$(basename "$f") no longer ends the session through logind"
done

# terminate-user takes down every session the user has, not just this one.
grep -q 'terminate-user' "$WLOGOUT" && fail "wlogout terminates the whole user again"

# Hyprland reports pid -1 for a window it cannot resolve, and `kill 0` signals
# the caller's whole process group.
grep -q 'filter(pid => pid > 0)' "$SESSION" \
    || fail "closeAllWindows no longer filters non-positive pids"
grep -q 'select(.pid > 0)' "$WLOGOUT" \
    || fail "wlogout no longer filters non-positive pids"

command -v jq > /dev/null || { printf 'jq is not installed; skipping jq check\n'; exit 0; }

# The jq the layout runs must drop a -1 and keep a real pid.
got="$(printf '[{"pid":-1},{"pid":0},{"pid":4242}]' \
    | jq -r '.[] | select(.pid > 0) | .pid' | tr '\n' ' ')"
[[ "$got" == "4242 " ]] || fail "pid filter kept something it should not: '$got'"

echo "ok"
