# shellcheck shell=bash
# Sourced by ./setup. Colours, logging, the confirm/run wrapper, and the file
# manifest that makes `setup uninstall` able to undo exactly what was installed.

XDG_BIN_HOME="${XDG_BIN_HOME:-$HOME/.local/bin}"
XDG_CACHE_HOME="${XDG_CACHE_HOME:-$HOME/.cache}"
XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'
    C_BLUE=$'\e[34m'; C_CYAN=$'\e[36m'; C_BOLD=$'\e[1m'; C_DIM=$'\e[2m'; C_RST=$'\e[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BLUE=''; C_CYAN=''; C_BOLD=''; C_DIM=''; C_RST=''
fi

KOOMPI_STATE_DIR="${XDG_STATE_HOME}/koompi"
MANIFEST="${KOOMPI_STATE_DIR}/installed-files"
SYSTEM_MANIFEST="${KOOMPI_STATE_DIR}/installed-system-files"
# Read by the `koompi update` helper, which has no other way to find the
# checkout. Keep the two in step if this ever moves.
REPO_PATH_FILE="${KOOMPI_STATE_DIR}/repo-path"
BACKUP_ROOT="${BACKUP_ROOT:-$HOME/.koompi-dots-backup}"
# Used by sdata/install/setups.sh and sdata/install/uninstall.sh.
# shellcheck disable=SC2034
VENV_DIR="${XDG_STATE_HOME}/quickshell/.venv"

ASSUME_YES="${ASSUME_YES:-false}"
DRY_RUN="${DRY_RUN:-false}"

step()    { printf '\n%s==> %s%s\n' "${C_BOLD}${C_CYAN}" "$*" "${C_RST}"; }
info()    { printf '%s  ->%s %s\n' "${C_BLUE}" "${C_RST}" "$*"; }
ok()      { printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RST}" "$*"; }
warn()    { printf '%s  !!%s %s\n' "${C_YELLOW}" "${C_RST}" "$*" >&2; }
err()     { printf '%s  xx%s %s\n' "${C_RED}" "${C_RST}" "$*" >&2; }
die()     { err "$*"; exit 1; }

have() { command -v "$1" >/dev/null 2>&1; }

# Run a command, echoing it first. Honours --dry-run. On failure the user
# chooses to retry, skip, or abort, because a half-installed desktop is worse
# than a stopped installer.
run() {
    printf '%s     $ %s%s\n' "${C_DIM}" "$*" "${C_RST}"
    if [[ "$DRY_RUN" == true ]]; then return 0; fi
    while ! "$@"; do
        err "command failed: $*"
        if [[ "$ASSUME_YES" == true ]]; then
            die "aborting (--yes means no interactive recovery)"
        fi
        local reply
        read -rp "  [r]etry / [s]kip / [a]bort (default abort): " reply
        case "$reply" in
            r|R) continue ;;
            s|S) warn "skipped: $*"; return 0 ;;
            *)   die "aborted" ;;
        esac
    done
    return 0
}

# run() from inside a directory, without the subshell that would swallow the
# abort. `( cd d && run cmd )` looks equivalent and is not: run's abort path
# calls die, die calls exit, and in a subshell that exit only ends the subshell.
# The caller then reads a non-zero return it never checks and carries on
# mutating the machine, which is exactly what "aborted" is supposed to prevent.
run_in_dir() {
    local dir="$1"; shift
    local prev="$PWD" rc=0
    cd -- "$dir" || die "cannot enter $dir"
    run "$@" || rc=$?
    cd -- "$prev" || die "cannot return to $prev"
    return "$rc"
}

# Stop processes by exact name, tolerating the ones that are not running.
# `killall a b c` exits non-zero when *any* name matched nothing, even after it
# killed the others, so putting it through run() turns "the daemon was already
# stopped" into a retry/skip/abort prompt and then an abort. The familiar
# `|| true` after run() does not save it either: run() calls die on abort, and
# die exits before the || can be reached. One name at a time, asked about
# first, so "not running" stays distinguishable from "could not kill".
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

# How many KOOMPI shells are running. The obvious `pgrep -fc 'qs -c koompi'` is
# the wrong tool: -f matches any process whose whole command line contains the
# pattern, which includes the terminal, editor or agent that happens to have
# the string on its own command line, and a -f based pkill will then kill them.
# Match the binary exactly and read each candidate's own cmdline instead.
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

confirm() {
    [[ "$ASSUME_YES" == true ]] && return 0
    local reply
    read -rp "${C_BOLD}$1${C_RST} [Y/n] " reply
    [[ -z "$reply" || "$reply" =~ ^[yY] ]]
}

require_not_root() {
    [[ "$(id -u)" -ne 0 ]] || die "do not run this as root or with sudo; it installs into \$HOME and calls sudo itself where needed"
}

# One sudo prompt up front, kept warm for the length of the install so package
# managers do not stall waiting for a password mid-download.
#
# The refresh must not give up on a single failure. A miss here is usually
# transient - `pacman -Syu` replacing the sudo binary, or /run/sudo/ts being
# recreated - and a loop that exits on it hands the rest of the install back to
# a password prompt at every one of the thirty-odd sudo calls that follow, which
# is exactly the behaviour this function exists to prevent. So keep looping, and
# refresh well inside the shortest timestamp_timeout worth supporting.
#
# A recorded PID is not evidence of a running keepalive, and the loop swallowing
# its own errors is not evidence that the ticket is warm. A build that takes
# forty minutes will happily run to the point where it needs root and only then
# discover neither is true, which puts a password prompt in the middle of a
# `makepkg` install phase. So the liveness of the process and the validity of
# the ticket are both checked, at boundaries we choose, by sudo_refresh.
SUDO_KEEPALIVE_PID=''
SUDO_KEEPALIVE_INTERVAL="${SUDO_KEEPALIVE_INTERVAL:-30}"

sudo_alive() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] || return 1
    kill -0 "$SUDO_KEEPALIVE_PID" 2>/dev/null
}

sudo_start() {
    have sudo || die "sudo not found; install it or run the per-distro dependency steps manually"
    [[ "$DRY_RUN" == true ]] && return 0
    sudo_alive && return 0
    info "requesting sudo once; it stays valid for the whole install"
    sudo -v || die "could not obtain sudo"
    ( while true; do sudo -n -v 2>/dev/null || true; sleep "$SUDO_KEEPALIVE_INTERVAL"; done ) &
    SUDO_KEEPALIVE_PID=$!
    sudo_alive || die "the sudo keepalive did not start"
}

# Call before anything long or anything that shells out to a tool which will
# sudo on its own. Re-prompting here is not a failure: it is the difference
# between one prompt at a step boundary the user is watching and one buried in
# a build, where pacman's --noconfirm has already taken the terminal.
sudo_refresh() {
    [[ "$DRY_RUN" == true ]] && return 0
    [[ -n "$SUDO_KEEPALIVE_PID" ]] || return 0

    if ! sudo_alive; then
        warn "the sudo keepalive stopped; restarting it"
        SUDO_KEEPALIVE_PID=''
        sudo_start
        return 0
    fi

    sudo -n -v 2>/dev/null && return 0
    warn "the sudo ticket went cold; re-authenticating here rather than mid-build"
    sudo -v || die "could not refresh sudo"
}

sudo_stop() {
    [[ -n "$SUDO_KEEPALIVE_PID" ]] || return 0
    kill "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    wait "$SUDO_KEEPALIVE_PID" 2>/dev/null || true
    SUDO_KEEPALIVE_PID=''
}

# Write a short root-owned file. Kept out of run() because the command there is
# echoed verbatim and a heredoc does not survive that.
sudo_write() {
    local path="$1" content="$2"
    printf '%s     $ write %s%s\n' "${C_DIM}" "$path" "${C_RST}"
    [[ "$DRY_RUN" == true ]] && return 0
    printf '%s\n' "$content" | sudo tee "$path" >/dev/null || die "could not write $path"
}

manifest_add() {
    [[ "$DRY_RUN" == true ]] && return 0
    mkdir -p "$(dirname "$MANIFEST")"
    printf '%s\n' "$1" >> "$MANIFEST"
}

manifest_finalize() {
    [[ -f "$MANIFEST" ]] || return 0
    local tmp
    tmp="$(mktemp)"
    sort -u -- "$MANIFEST" > "$tmp" && mv -f -- "$tmp" "$MANIFEST"
}

# Where the checkout that installed this desktop lives. `koompi update` runs
# from $PATH with no idea where the repo is, and asking the user to remember is
# the kind of thing that makes people stop updating.
record_repo_path() {
    [[ "$DRY_RUN" == true ]] && return 0
    mkdir -p "$KOOMPI_STATE_DIR"
    printf '%s\n' "$REPO_ROOT" > "$REPO_PATH_FILE"
}

# Pick up new config in the running session. Reloading Hyprland is cheap and
# safe; the shell has to be restarted outright because Quickshell does not
# reliably hot-reload a changed tree.
#
# The QT_QPA_PLATFORM override matters: hyprland/env.lua puts the session on xcb
# so the global menu works, and a Quickshell that inherits that maps no layer
# surfaces at all - the bar and sidebars come back invisible. Same reasoning as
# the CTRL+SUPER+R bind in hyprland/keybinds.lua, which is why they are written
# the same way.
reload_session() {
    have hyprctl || return 0
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] || {
        info "not inside a Hyprland session; the new config loads at your next login"
        return 0
    }
    step "Reloading the running session"
    run hyprctl reload
    have qs || return 0

    # global-menu-daemon is started by the shell itself
    # (services/GlobalMenuService.qml), so relaunching qs is what brings it back.
    stop_processes global-menu-daemon qs quickshell
    if [[ "$DRY_RUN" == true ]]; then
        info "would restart the shell"
        return 0
    fi
    ( setsid env QT_QPA_PLATFORM=wayland qs -c koompi >/dev/null 2>&1 & )

    # Reporting "shell restarted" unconditionally is worse than saying nothing:
    # the one run where the message matters is the run where the shell did not
    # come back, and that is precisely the run where it lies. Ask the system.
    local waited=0 count=0
    while :; do
        count="$(count_shells)"
        (( count > 0 )) && break
        (( waited >= 10 )) && break
        sleep 1
        waited=$((waited + 1))
    done
    case "$count" in
        0) warn "the shell did not come back within ${waited}s; run 'qs -c koompi' to see why" ;;
        1) ok "shell restarted" ;;
        *) warn "$count koompi shells are running where there should be one" ;;
    esac
}
