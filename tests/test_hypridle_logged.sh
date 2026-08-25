#!/usr/bin/env bash
# hypridle used to be exec-once'd by execs.lua with its output on /dev/null, so
# whether the login-time instance relayed logind's Lock to the shell could not
# be read from any log (J15 finding 3). It now runs as the packaged user unit,
# WantedBy=graphical-session.target: journal output, restart on crash, one
# instance per session. This checks each half of that wiring stays in place,
# and, inside a session where the unit is running, that a Lock reaches it.
#
# The live check calls `loginctl lock-session`, so it locks the screen. Outside
# a session with hypridle.service active it says so and skips.
#
# The stubs below are called from inside setup_services, never via sudo here.
# shellcheck disable=SC2329,SC2032
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
EXECS="$ROOT/dots/.config/hypr/hyprland/execs.lua"
SETUPS="$ROOT/sdata/install/setups.sh"
UNIT=/usr/lib/systemd/user/hypridle.service

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. No bare exec. `hl.exec_cmd("hypridle")` is the /dev/null instance, and
#    alongside the unit it would be a second daemon running every lock_cmd twice.
grep -nE 'exec_cmd\(["'"'"'][^"'"'"']*\bhypridle\b' "$EXECS" \
    && fail "execs.lua starts hypridle by hand again; the packaged unit owns it"

# 2. The unit's ConditionEnvironment=WAYLAND_DISPLAY is checked when
#    graphical-session.target is pulled in, so the line that starts the target
#    has to import the display into the manager first, in the same command.
target_line="$(grep -E 'systemctl --user start hyprland-session\.target' "$EXECS")"
[[ -n "$target_line" ]] || fail "execs.lua no longer starts hyprland-session.target"
[[ "$target_line" == *"dbus-update-activation-environment --systemd"*WAYLAND_DISPLAY*"systemctl --user start hyprland-session.target"* ]] \
    || fail "WAYLAND_DISPLAY is not imported into the user manager before hyprland-session.target starts; hypridle.service would be skipped on its condition"

# 3. setup_services enables the unit (and only when a user manager is there).
#    Sourced with the installer's helpers stubbed; `run` records instead of acting.
step() { :; }; info() { :; }; ok() { :; }; warn() { printf 'warn: %s\n' "$*" >> "$tmp/warn.log"; }
have() { return 0; }
run() { printf '%s\n' "$*" >> "$tmp/run.log"; }
python3() { return 1; }   # no evdev: keeps touch-gestures out of the log
systemctl() { return 1; } # bluetooth probe: nothing to enable
# shellcheck source=sdata/install/setups.sh
source "$SETUPS" 2>/dev/null || true
declare -F setup_services >/dev/null || fail "setups.sh no longer defines setup_services"

systemd_running() { return 0; }
systemd_user_running() { return 0; }
: > "$tmp/run.log"; : > "$tmp/warn.log"
if [[ -e "$UNIT" ]]; then
    setup_services
    grep -Fxq 'systemctl --user enable hypridle' "$tmp/run.log" \
        || fail "setup_services does not enable hypridle: $(tr '\n' ';' < "$tmp/run.log")"
    grep -Fq 'enable --now hypridle' "$tmp/run.log" \
        && fail "setup_services enables hypridle with --now; in a session still running the old exec that is two daemons"
fi

systemd_user_running() { return 1; }
: > "$tmp/run.log"; : > "$tmp/warn.log"
setup_services
grep -Fq 'hypridle' "$tmp/run.log" \
    && fail "setup_services touches hypridle without a user manager to enable it in"
grep -Fq 'hypridle' "$tmp/warn.log" \
    || fail "setup_services says nothing about hypridle when it cannot enable it"
unset -f systemctl python3

# 4. The packaged unit itself: journal output (no StandardOutput/Error=null),
#    tied to the session, restarts on crash.
if [[ ! -e "$UNIT" ]]; then
    echo "hypridle not installed; skipping the unit and live checks"
    exit 0
fi
grep -qE '^Standard(Output|Error)=null' "$UNIT" \
    && fail "$UNIT discards its output; the journal is the point"
grep -qE '^ExecStart=.*hypridle' "$UNIT"            || fail "$UNIT does not start hypridle"
grep -qx 'PartOf=graphical-session.target' "$UNIT"  || fail "$UNIT is not PartOf=graphical-session.target"
grep -qx 'WantedBy=graphical-session.target' "$UNIT" || fail "$UNIT is not WantedBy=graphical-session.target"
grep -qE '^Restart=(on-failure|always)' "$UNIT"      || fail "$UNIT does not restart on crash"

# 5. Live: a logind Lock reaches the unit within 2 s. Needs the unit running
#    under this user's manager inside an active logind session.
if [[ -z "${XDG_SESSION_ID:-}" ]] \
   || [[ "$(loginctl show-session "$XDG_SESSION_ID" -p State --value 2>/dev/null)" != active ]] \
   || [[ "$(command systemctl --user is-active hypridle.service 2>/dev/null)" != active ]]; then
    echo "skip: no active logind session with hypridle.service running; the live Lock check needs a login"
    exit 0
fi
since="$(date '+%Y-%m-%d %H:%M:%S')"
loginctl lock-session || fail "loginctl lock-session failed"
for _ in $(seq 1 20); do
    if journalctl --user -u hypridle.service --since "$since" --no-pager -o short-precise 2>/dev/null \
            | grep -q 'Got Lock from dbus'; then
        echo "ok: hypridle.service logged 'Got Lock from dbus' for loginctl lock-session"
        exit 0
    fi
    sleep 0.1
done
fail "hypridle.service did not log 'Got Lock from dbus' within 2 s of loginctl lock-session: $(journalctl --user -u hypridle.service --since "$since" --no-pager -o short-precise 2>&1 | tail -5)"
