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

# scripts/global-menu/build.zig.zon floors at 0.16.0, and a distro zig is not
# enough on its own: Debian 13 has no zig at all and Ubuntu's `zig` metapackage
# still points at 0.14, which fails the build rather than skipping it.
ZIG_MIN=0.16.0
zig_usable() {
    have zig || return 1
    local v core
    v="$(zig version 2>/dev/null)" || return 1
    core="${v%%-*}"
    # sort -V ranks 0.16.0-dev above 0.16.0; semver, and zig's own
    # minimum_zig_version, rank it below. Refuse a pre-release of the floor
    # itself and let sort decide the rest.
    [[ "$core" == "$v" || "$core" != "$ZIG_MIN" ]] || return 1
    # Already-sorted check: true when ZIG_MIN <= core.
    printf '%s\n%s\n' "$ZIG_MIN" "$core" | sort -C -V
}

# globalmenu/Cargo.toml floors at 1.87, which is zbus 5's own floor. Parsed
# rather than probed for the same reason as zig: a distro rustc that is present
# but too old fails the build instead of skipping it.
RUST_MIN=1.87
cargo_usable() {
    have cargo || return 1
    local v
    # `cargo 1.97.1 (c980f4866 2026-06-30)`
    v="$(cargo --version 2>/dev/null | awk '{print $2}')" || return 1
    [[ -n "$v" ]] || return 1
    printf '%s\n%s\n' "$RUST_MIN" "$v" | sort -C -V
}

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

# run() for a step the install can live without: the failure is returned rather
# than turned into a prompt or a die, so the caller says what was lost and
# carries on. `run cmd || warn` cannot express that - run() calls die under
# --yes, and die exits before the || is reached.
try() {
    printf '%s     $ %s%s\n' "${C_DIM}" "$*" "${C_RST}"
    [[ "$DRY_RUN" == true ]] && return 0
    "$@"
}

# run() from inside a directory without the subshell that would swallow the abort.
# `( cd d && run cmd )` is not equivalent: run aborts via die, die is exit, and in a
# subshell that ends only the subshell. The caller then reads a status it never
# checks and carries on mutating the machine.
run_in_dir() {
    local dir="$1"; shift
    local prev="$PWD" rc=0
    cd -- "$dir" || die "cannot enter $dir"
    run "$@" || rc=$?
    cd -- "$prev" || die "cannot return to $prev"
    return "$rc"
}

# `killall a b c` exits non-zero when ANY name matched nothing, even after killing
# the others, so through run() "already stopped" becomes a retry/skip/abort prompt.
# A trailing `|| true` does not save it either: run() calls die, and die exits before
# the || is reached. One name at a time, asked about first.
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

# Not `pgrep -fc 'qs -c koompi'`: -f matches any process whose whole command line
# contains the pattern, which includes the terminal, editor or agent that happens to
# have the string on it - and an -f based pkill then kills them. Match the binary
# exactly and read each candidate's own cmdline.
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

# One sudo prompt up front, kept warm so package managers do not stall mid-download.
#
# The refresh must not give up on a single failure: a miss is usually transient
# (pacman replacing the sudo binary, /run/sudo/ts recreated) and a loop that exits
# hands the rest of the install back to a prompt at every sudo call that follows.
# Refresh well inside the shortest timestamp_timeout worth supporting.
#
# A recorded PID is not a running keepalive and a loop swallowing its own errors is
# not a warm ticket, so sudo_refresh checks both at boundaries we choose.
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
    # Not every one of these directories is on every machine. Nothing on Debian
    # had ever created /usr/lib/systemd/system-sleep, so the suspend hook took
    # the install down with a bare "No such file or directory" from tee.
    local dir; dir="$(dirname -- "$path")"
    sudo mkdir -p -- "$dir" || die "could not create $dir"
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

# Reloading Hyprland is cheap; the shell is restarted outright because Quickshell
# does not reliably hot-reload a changed tree.
#
# The QT_QPA_PLATFORM override matters: hyprland/env.lua puts the session on xcb so
# the global menu works, and a Quickshell that inherits it maps no layer surfaces at
# all. Same reasoning as the CTRL+SUPER+R bind in hyprland/keybinds.lua.
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
