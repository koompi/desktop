# shellcheck shell=bash
# Sourced by libexec/update and bin/koompi-reload, never run. Messages, the
# process helpers, and the J24 guards (audit O02 O10 O21).

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m'; C_CYAN=$'\e[36m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RST=''
fi

step() { printf '\n%s==> %s%s\n' "${C_BOLD}${C_CYAN}" "$*" "${C_RST}"; }
info() { printf '%s  ->%s %s\n' "${C_BLUE}" "${C_RST}" "$*"; }
ok()   { printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RST}" "$*"; }
warn() { printf '%s  !!%s %s\n' "${C_YELLOW}" "${C_RST}" "$*" >&2; }
die()  { printf '%s  xx%s %s\n' "${C_RED}" "${C_RST}" "$*" >&2; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

: "${DRY_RUN:=false}"

run() {
    printf '%s     $ %s%s\n' "${C_DIM}" "$*" "${C_RST}"
    [[ "$DRY_RUN" == true ]] && return 0
    "$@"
}

# kept in step with sdata/lib/common.sh, which the installed scripts cannot source
stop_processes() {
    local name
    for name in "$@"; do
        printf '%s     $ killall -w -q %s%s\n' "${C_DIM}" "$name" "${C_RST}"
        [[ "$DRY_RUN" == true ]] && continue
        pgrep -x -- "$name" >/dev/null 2>&1 || continue
        killall -w -q -- "$name" 2>/dev/null || warn "could not stop $name"
    done
    return 0
}

count_shells() {
    local pid n=0
    while read -r pid; do
        [[ -n "$pid" ]] || continue
        if tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | grep -qF -- '-c koompi'; then
            n=$((n + 1))
        fi
    done < <(pgrep -x qs 2>/dev/null)
    printf '%s\n' "$n"
}

LOCK_FILE="${TMPDIR:-/tmp}/koompi-update-$(id -u).lock"
[[ -d "${XDG_RUNTIME_DIR:-}" && -w "${XDG_RUNTIME_DIR:-}" ]] && LOCK_FILE="$XDG_RUNTIME_DIR/koompi-update.lock"

# flock(1) not a bash fd: a bash fd leaks into the restarted qs and holds the lock till logout; -o closes it pre-exec
run_locked() {
    have flock || die "flock (util-linux) is required"
    KOOMPI_UPDATE_LOCKED=1 flock -n -E 75 -o "$LOCK_FILE" "$BASH" "$0" "$@"
    local rc=$?
    (( rc == 75 )) || exit "$rc"
    local pid; pid="$(tr -dc '0-9' < "$LOCK_FILE" 2>/dev/null | head -c 20)"
    die "another koompi update is running (pid ${pid:-unknown})"
}

# same classes as services/Idle.qml: logind weighs the lid against handle-lid-switch alone; tail --pid self-ends if this run dies
INHIBIT_PID=""
stay_awake() {
    local -a cmd=(systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block --who=koompi-update --why='KOOMPI update in progress')
    have systemd-inhibit || { warn "systemd-inhibit not found; the machine may sleep or suspend during the upgrade"; return 0; }
    printf '%s     $ %s%s\n' "${C_DIM}" "${cmd[*]} tail --pid=$$ -f /dev/null" "${C_RST}"
    [[ "$DRY_RUN" == true ]] && return 0
    "${cmd[@]}" tail --pid=$$ -f /dev/null </dev/null >/dev/null 2>&1 &
    INHIBIT_PID=$!
    trap 'kill "$INHIBIT_PID" 2>/dev/null' EXIT
}

# 2 GiB not omarchy's 10: 64 GB eMMC school laptops; covers the download, pacman CheckSpace covers the install
require_free_space() {
    local path="$1" need_gib=2 avail_kib avail_gib
    avail_kib="$(df -Pk -- "$path" 2>/dev/null | awk 'NR == 2 { print $4 }')"
    [[ "$avail_kib" =~ ^[0-9]+$ ]] || die "cannot read the free space on $path (df failed)"
    avail_gib="$(awk -v k="$avail_kib" 'BEGIN { printf "%.1f", k / 1048576 }')"
    (( avail_kib >= need_gib * 1048576 )) \
        || die "only ${avail_gib} GiB free on $path; koompi update needs ${need_gib} GiB. Free some space and run it again"
    info "free space on $path: ${avail_gib} GiB (needs ${need_gib} GiB)"
}

# no qs ipc target for screenLocked; the shell mirrors it to logind LockedHint
# (modules/common/panels/lock/LockScreen.qml setLockedHint), readable from ssh; hyprlock sets none
session_locked() {
    local id
    while read -r id _; do
        [[ "$(loginctl show-session "$id" -p LockedHint --value 2>/dev/null)" == yes ]] && return 0
    done < <(loginctl list-sessions --no-legend 2>/dev/null | awk -v uid="$(id -u)" '$2 == uid { print $1 }')
    pgrep -x hyprlock >/dev/null 2>&1
}

REBOOT_REASON=""
check_restart_needed() {
    local running newest dir pid
    running="$(uname -r)"
    # KOOMPI_UPDATE_MODULES_DIR: test hook (tests/test_update_guards.sh)
    newest="$(for dir in "${KOOMPI_UPDATE_MODULES_DIR:-/usr/lib/modules}"/*/; do
                  [[ -f "$dir/vmlinuz" ]] && basename "$dir"; done | sort -V | tail -1)"
    [[ -n "$newest" && "$newest" != "$running" ]] \
        && REBOOT_REASON="kernel $newest is installed but $running is running"
    pid="$(pidof -s Hyprland 2>/dev/null)" || return 0
    [[ "$(readlink "/proc/$pid/exe" 2>/dev/null)" == *' (deleted)' ]] \
        && REBOOT_REASON="${REBOOT_REASON:+$REBOOT_REASON; }the Hyprland binary was replaced under the running compositor"
    return 0
}
