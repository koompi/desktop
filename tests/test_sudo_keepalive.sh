#!/usr/bin/env bash
# Guards the keepalive's only failure mode: a password prompt mid-run, inside a
# makepkg install phase --noconfirm has already taken the terminal for. It could not
# be shown to be working, because `sudo -n -v 2>/dev/null || true` threw its signal
# away - a recorded PID is not a running process and a loop that swallows its errors
# is not a warm ticket. Asserts both against a stubbed sudo.
#
# No real sudo is invoked and no password is read: the stub is first on PATH.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
stub="$tmp/bin"
mkdir -p "$stub"
export SUDO_LOG="$tmp/sudo.log"
export SUDO_COLD="$tmp/cold"
: > "$SUDO_LOG"

cat > "$stub/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SUDO_LOG"
# `sudo -n -v` is the non-interactive refresh: it is the call that fails once
# the timestamp has gone cold. `sudo -v` is the interactive re-prime, which the
# stub always lets through.
[[ "$*" == "-n -v" && -e "$SUDO_COLD" ]] && exit 1
exit 0
EOF
chmod +x "$stub/sudo"
PATH="$stub:$PATH"

# shellcheck source=sdata/lib/common.sh
source "$REPO_ROOT/sdata/lib/common.sh"

cleanup() { sudo_stop; rm -rf "$tmp"; }
trap cleanup EXIT

fail() { printf '%s\n--- sudo calls ---\n%s\n' "$1" "$(cat "$SUDO_LOG")" >&2; exit 1; }

SUDO_KEEPALIVE_INTERVAL=1   # drive the loop fast enough to observe

sudo_start
first_pid="$SUDO_KEEPALIVE_PID"
[[ -n "$first_pid" ]] || fail 'sudo_start recorded no keepalive PID'

# 1. The process survives a long foreground command, and actually refreshes
#    while it runs. This is the property the reported failure disproved.
: > "$SUDO_LOG"
sleep 3
sudo_alive || fail 'the keepalive died during a foreground command'
refreshes="$(grep -cFx -- '-n -v' "$SUDO_LOG")"
(( refreshes >= 2 )) || fail "the keepalive refreshed $refreshes time(s) in 3s at a 1s interval"

# 2. A dead keepalive is noticed and restarted, rather than believed because a
#    PID variable is still set.
kill "$first_pid" 2>/dev/null
wait "$first_pid" 2>/dev/null
sudo_alive && fail 'sudo_alive reported a killed keepalive as running'

: > "$SUDO_LOG"
sudo_refresh
sudo_alive || fail 'sudo_refresh did not restart the dead keepalive'
[[ "$SUDO_KEEPALIVE_PID" != "$first_pid" ]] || fail 'sudo_refresh kept the dead PID'

# 3. A live keepalive whose ticket has gone cold re-primes here, at a boundary
#    the caller chose, instead of letting the next sudo prompt inside a build.
touch "$SUDO_COLD"
: > "$SUDO_LOG"
sudo_refresh
grep -qFx -- '-v' "$SUDO_LOG" ||
    fail 'a cold ticket did not trigger the interactive re-prime'
rm -f "$SUDO_COLD"

# 4. sudo_stop leaves nothing behind.
last_pid="$SUDO_KEEPALIVE_PID"
sudo_stop
[[ -z "$SUDO_KEEPALIVE_PID" ]] || fail 'sudo_stop left a PID recorded'
kill -0 "$last_pid" 2>/dev/null && fail 'sudo_stop left the keepalive running'

printf 'sudo keepalive test passed\n'
