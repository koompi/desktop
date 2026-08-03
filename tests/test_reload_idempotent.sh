#!/usr/bin/env bash
# Guards: a reload must not abort on a daemon that was not running. killall exits
# non-zero when ANY name matched nothing, and the `|| true` after it was dead code -
# run() calls die on abort and die exits before || is reached.
#
# killall, pgrep, hyprctl and setsid are shadowed; the session's own shell is never
# in the stub's answers.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

tmp="$(mktemp -d)"
stub="$tmp/bin"
mkdir -p "$stub"
export KILLALL_LOG="$tmp/killall.log"
: > "$KILLALL_LOG"

# A stand-in for the restarted shell: a real process whose name is `qs` and
# whose command line carries `-c koompi`, so count_shells has something honest
# to read out of /proc. `; :` keeps bash from exec-optimising the sleep, which
# would replace the process name.
ln -s "$(command -v bash)" "$stub/qs"
"$stub/qs" -c 'sleep 30; :' -c koompi &
export FAKE_QS_PID=$!

cleanup() { kill "$FAKE_QS_PID" 2>/dev/null; wait "$FAKE_QS_PID" 2>/dev/null; rm -rf "$tmp"; }
trap cleanup EXIT

cat > "$stub/pgrep" <<'EOF'
#!/usr/bin/env bash
name="${!#}"
case "$name" in
    # The case that used to abort the whole update: the daemon is not running,
    # because the shell that starts it has just been stopped.
    global-menu-daemon) exit 1 ;;
    quickshell)         exit 1 ;;
    qs)                 printf '%s\n' "$FAKE_QS_PID"; exit 0 ;;
esac
exit 1
EOF

cat > "$stub/killall" <<'EOF'
#!/usr/bin/env bash
# Faithful to psmisc killall: a name that matched nothing makes the whole call
# exit non-zero, even when the other names were killed successfully.
rc=0
for arg in "$@"; do
    case "$arg" in
        -*|--) continue ;;
        qs)    printf '%s\n' "$arg" >> "$KILLALL_LOG" ;;
        *)     rc=1 ;;
    esac
done
exit "$rc"
EOF

printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/hyprctl"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/setsid"
chmod +x "$stub"/pgrep "$stub"/killall "$stub"/hyprctl "$stub"/setsid
PATH="$stub:$PATH"

# shellcheck source=sdata/lib/common.sh
source "$REPO_ROOT/sdata/lib/common.sh"

HYPRLAND_INSTANCE_SIGNATURE=test-session
ASSUME_YES=false   # so a prompt would be a real prompt

out="$tmp/out"
# stdin is closed: if anything asks the user a question, read gets EOF, run()
# takes the default branch and dies, and the status below is non-zero.
reload_session > "$out" 2>&1 < /dev/null
status=$?

fail() { printf '%s\n--- output ---\n%s\n' "$1" "$(cat "$out")" >&2; exit 1; }

(( status == 0 )) ||
    fail "reload_session returned $status when one of the named processes was simply not running"

grep -q 'retry' "$out" && fail 'reload_session prompted the user'
grep -q 'aborted' "$out" && fail 'reload_session aborted'

# Only the process that was actually running should have been killed. Handing
# killall a name that is not running is what produced the non-zero status.
killed="$(sort -u "$KILLALL_LOG")"
[[ "$killed" == "qs" ]] ||
    fail "expected killall to be called for qs alone, got: ${killed:-<none>}"

# And the outcome has to be reported from what is running, not asserted.
grep -q 'shell restarted' "$out" ||
    fail 'reload_session did not confirm the shell came back'

printf 'reload idempotency test passed\n'
