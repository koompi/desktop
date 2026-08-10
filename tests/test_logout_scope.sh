#!/usr/bin/env bash
# Logging out has to end the calling session and nothing else, and it has to leave
# SDDM able to put the greeter back. Three shapes have broken that:
#   - `pkill -i Hyprland`, which matches every compositor the user owns;
#   - killing only the compositor, which leaves the rest of the session in a scope
#     logind waits on forever (KillUserProcesses=no);
#   - `loginctl terminate-session` on its own, which SIGTERMs the session leader -
#     sddm-helper - so SDDM sees exit 1, calls it a crash and never respawns.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SESSION="$ROOT/dots/.config/quickshell/koompi/modules/common/functions/Session.qml"
WLOGOUT="$ROOT/dots/.config/wlogout/layout"
LOGOUT="$ROOT/dots/.local/bin/koompi-logout"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

for f in "$SESSION" "$WLOGOUT"; do
    # Comments here explain the old pkill on purpose, so only look at code.
    sed 's|//.*||' "$f" | grep -qE 'pkill[^"]*[Hh]yprland' \
        && fail "$(basename "$f") logs out with an unscoped pkill again"
    sed 's|//.*||' "$f" | grep -q 'terminate-session' \
        && fail "$(basename "$f") terminates the session inline again, which kills sddm-helper"
    grep -q 'koompi-logout' "$f" \
        || fail "$(basename "$f") no longer logs out through koompi-logout"
done

# terminate-user takes down every session the user has, not just this one.
grep -q 'terminate-user' "$WLOGOUT" && fail "wlogout terminates the whole user again"

# Hyprland reports pid -1 for a window it cannot resolve, and `kill 0` signals
# the caller's whole process group.
grep -q 'filter(pid => pid > 0)' "$SESSION" \
    || fail "closeAllWindows no longer filters non-positive pids"
grep -q 'select(.pid > 0)' "$WLOGOUT" \
    || fail "wlogout no longer filters non-positive pids"

[[ -x "$LOGOUT" ]] || fail "koompi-logout is not executable"

# Run it against a fake leader and fake tools: the sweep must land only after the
# leader has exited, or SDDM gets the crash it cannot recover from.
sleep 30 &
leader=$!
mkdir -p "$tmp/bin"

cat > "$tmp/bin/loginctl" << EOF
#!/usr/bin/env bash
case "\$*" in
    *Leader*) echo $leader ;;
    terminate-session*)
        kill -0 $leader 2> /dev/null && echo leader-alive >> "$tmp/log"
        echo swept >> "$tmp/log"
        ;;
esac
EOF

cat > "$tmp/bin/hyprctl" << EOF
#!/usr/bin/env bash
echo exited >> "$tmp/log"
( sleep 0.3; kill $leader 2> /dev/null ) &
EOF

# pgrep is stubbed away so the escalation path can never reach the compositor of
# whoever is running this suite.
printf '#!/usr/bin/env bash\nexit 1\n' > "$tmp/bin/pgrep"

chmod +x "$tmp/bin/loginctl" "$tmp/bin/hyprctl" "$tmp/bin/pgrep"

run_logout() { PATH="$tmp/bin:$PATH" KOOMPI_LOGOUT_GRACE=2 KOOMPI_LOGOUT_KILL_GRACE=1 "$@" "$LOGOUT"; }

run_logout env XDG_SESSION_ID=42 || fail "koompi-logout exited non-zero"
wait "$leader" 2> /dev/null || true

got="$(tr '\n' ' ' < "$tmp/log")"
[[ "$got" == "exited swept " ]] \
    || fail "koompi-logout did not exit the compositor then sweep: '$got'"

# The seat failure of 2026-08-10: hyprctl accepted the command and exited
# nothing, the wait timed out, and the sweep ran anyway - SIGTERMing sddm-helper,
# which is the black screen this script exists to prevent. A leader that never
# exits must cost a failed logout, never a swept session.
: > "$tmp/log"
sleep 30 &
leader=$!
cat > "$tmp/bin/loginctl" << EOF
#!/usr/bin/env bash
case "\$*" in
    *Leader*) echo $leader ;;
    terminate-session*) echo swept >> "$tmp/log" ;;
esac
EOF
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/hyprctl"
chmod +x "$tmp/bin/loginctl" "$tmp/bin/hyprctl"

run_logout env XDG_SESSION_ID=42 && fail "koompi-logout reported success while the session leader was still alive"
grep -q swept "$tmp/log" && fail "koompi-logout swept the scope with the leader alive, which is the SDDM black screen"
kill "$leader" 2> /dev/null || true
wait "$leader" 2> /dev/null || true

# The command has to be one the running compositor actually understands. Under
# the lua config `dispatch exit` is the undefined identifier `exit`, so it
# parses, dispatches nothing, and reports success - exactly how this shipped
# broken. Ask the live compositor which dispatchers exist.
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] && command -v hyprctl > /dev/null; then
    dispatcher="$(grep -o "hl\.dsp\.[a-z_]*" "$LOGOUT" | head -1 | sed 's/hl\.dsp\.//')"
    [[ -n "$dispatcher" ]] || fail "koompi-logout no longer names an hl.dsp dispatcher"
    # The probe raises so it can report the table without dispatching anything,
    # so hyprctl answering non-zero is the success path.
    known="$(hyprctl dispatch '(function() local t={} for k in pairs(hl.dsp) do t[#t+1]=k end error(table.concat(t,","),0) end)()' 2>&1 || true)"
    case ",${known#error: }," in
        *",$dispatcher,"*) ;;
        *) fail "hl.dsp.$dispatcher is not a dispatcher this Hyprland knows: $known" ;;
    esac
fi

# No session id (started outside logind) must not fall through to a bare sweep.
: > "$tmp/log"
PATH="$tmp/bin:$PATH" env -u XDG_SESSION_ID "$LOGOUT" || fail "koompi-logout failed without a session id"
grep -q swept "$tmp/log" && fail "koompi-logout swept a session it could not identify"

echo "ok"
