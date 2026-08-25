# shellcheck shell=bash
# migrate-lib.sh - the subcommands of koompi-migrate that are not the sync:
# `notify`, `refresh`, `new`, and the Hyprland autoreload guard the sync uses.
# Sourced by koompi-migrate (next to it in the dots tree, /usr/lib/koompi when
# packaged); every variable it reads (SELF, HOME, SKEL, XDG_SYS, BACKUP_DIR,
# migrations_dir, pending_migrations, die) comes from the caller.

notification_server_ready() {
    [[ "$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus NameHasOwner s org.freedesktop.Notifications 2>/dev/null)" == "b true" ]]
}

# Terminal order follows variables.lua's `terminal` (launch_first_available.sh
# 'wezterm' 'foot' 'kitty -1' ...). One argv element per line: the terminal
# plus its own "run this command" spelling, never a shell string to eval.
terminal_argv() {
    local t
    for t in wezterm foot kitty alacritty konsole kgx uxterm xterm; do
        command -v "$t" >/dev/null || continue
        case "$t" in
            wezterm) printf '%s\n' wezterm start -- ;;
            foot)    printf '%s\n' foot ;;
            kitty)   printf '%s\n' kitty -1 ;;
            kgx)     printf '%s\n' kgx -- ;;
            *)       printf '%s\n' "$t" -e ;;
        esac
        return 0
    done
    return 1
}

notify_pending() {
    local dir pending n wait tries sender term=()
    dir="$(migrations_dir || true)"
    mapfile -t pending < <(pending_migrations "$dir")
    [[ ${#pending[@]} -gt 0 ]] || exit 0
    n=${#pending[@]}
    # graphical-session.target is reached before the shell owns
    # org.freedesktop.Notifications, and a toast sent before that is lost
    # (omarchy bin/omarchy-notification-wait:8-13). NameHasOwner rather than
    # a Notify call: a call would D-Bus-activate whatever daemon claims the name.
    wait="${KOOMPI_MIGRATE_NOTIFY_WAIT:-60}"
    tries=$((wait * 10))
    until notification_server_ready; do
        (( tries-- > 0 )) || die "no notification server after ${wait}s; $n migration(s) pending, run 'koompi-migrate run'"
        sleep 0.1
    done
    sender="$(command -v koompi-notify-send || true)"
    [[ -n "$sender" ]] || sender="$(dirname -- "$SELF")/koompi-notify-send"
    [[ -x "$sender" ]] || die "koompi-notify-send not found"
    mapfile -t term < <(terminal_argv || true)
    if [[ ${#term[@]} -gt 0 ]]; then
        "$sender" -a KOOMPI -u critical "Desktop update pending" \
            "Click to run $n pending migration(s), or run 'koompi-migrate run' in a terminal." \
            --exec "${term[@]}" "$SELF" run --hold
    else
        "$sender" -a KOOMPI -u critical "Desktop update pending" \
            "Run 'koompi-migrate run' in a terminal to finish it ($n pending)."
    fi
}

# Hyprland reloads its config on every write under ~/.config/hypr, and a
# reload halfway through an rsync of hyprland/ is a black screen. The watcher
# is paused for the sync and put back from an EXIT trap, so a failed rsync
# cannot leave it off. Restores the value found, not a hardcoded 0.
autoreload_prev=""
pause_autoreload() {
    if [[ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
        echo "  note  not inside a Hyprland session; autoreload guard skipped"
        return 0
    fi
    command -v hyprctl >/dev/null || { echo "  note  hyprctl not found; autoreload guard skipped"; return 0; }
    autoreload_prev="$(hyprctl -j getoption misc:disable_autoreload 2>/dev/null | jq -r '.bool' 2>/dev/null || true)"
    [[ "$autoreload_prev" == true ]] || autoreload_prev=false
    trap resume_autoreload EXIT
    hyprctl keyword misc:disable_autoreload 1 >/dev/null || die "hyprctl keyword misc:disable_autoreload failed; not syncing under a live watcher"
}
resume_autoreload() {
    [[ -n "$autoreload_prev" ]] || return 0
    hyprctl keyword misc:disable_autoreload "$autoreload_prev" >/dev/null \
        || echo "koompi-migrate: could not restore misc:disable_autoreload=$autoreload_prev; run 'koompi reload'" >&2
    autoreload_prev=""
}

# Put the packaged default back for one file. The backup goes next to the
# sync's tarballs so there is one place to look for "what did I have before".
refresh_file() {
    local rel="$1" src dst backup
    rel="${rel#"$HOME"/}"; rel="${rel#\~/}"
    case "$rel" in
        /*|..|../*|*/../*|*/..|"") die "refresh wants a path under ~ such as .config/hypr/hypridle.conf" ;;
    esac
    # `hypr/hypridle.conf` is accepted as shorthand for `.config/hypr/hypridle.conf`.
    [[ -e "$SKEL/$rel" || "$rel" == .config/* ]] || rel=".config/$rel"
    dst="$HOME/$rel"
    if [[ "$rel" == .config/quickshell/koompi/* && -f "$XDG_SYS/quickshell/koompi/${rel#.config/quickshell/koompi/}" ]]; then
        src="$XDG_SYS/quickshell/koompi/${rel#.config/quickshell/koompi/}"
    elif [[ -f "$SKEL/$rel" ]]; then
        src="$SKEL/$rel"
    else
        die "no packaged default for $rel; defaults live in $SKEL (dotfiles) and $XDG_SYS/quickshell/koompi (shell)"
    fi
    [[ ! -d "$dst" ]] || die "$rel is a directory; refresh takes one file (the plain sync covers trees)"
    if [[ -f "$dst" ]]; then
        if cmp -s -- "$src" "$dst"; then
            echo "koompi-migrate: ${dst/#$HOME/\~} already matches the packaged default"
            return 0
        fi
        mkdir -p "$BACKUP_DIR"
        backup="${rel#.}"; backup="$BACKUP_DIR/refresh-$(date +%Y%m%d-%H%M%S)-${backup//\//_}"
        cp -p -- "$dst" "$backup"
        echo "  backup written: ${backup/#$HOME/\~}"
        # diff exits 1 when the files differ, which is the whole point here.
        diff -u --label "$rel (yours)" --label "$rel (packaged)" -- "$dst" "$src" || [[ $? -eq 1 ]]
    else
        echo "  no ${dst/#$HOME/\~} yet; installing the packaged default"
        mkdir -p -- "$(dirname -- "$dst")"
    fi
    cp -- "$src" "$dst"
    echo "koompi-migrate: ${dst/#$HOME/\~} replaced with the packaged default"
}

# Skeleton for a new migration in this checkout. The timestamp prefix sorts
# chronologically, which is the run order, and the filename is the per-user
# completion marker, so it must never change once shipped.
new_migration() {
    local slug="$1" repo_root file
    [[ "$slug" =~ ^[a-z0-9]+(-[a-z0-9]+)*$ ]] || die "slug must be lowercase words joined by hyphens, e.g. relink-nvim-theme"
    repo_root="$(cd -- "$(dirname -- "$SELF")/../../.." 2>/dev/null && pwd)" || repo_root=""
    [[ -n "$repo_root" && -e "$repo_root/.git" && -d "$repo_root/sdata/migrations" ]] \
        || die "new only works from a checkout (dots/.local/bin/koompi-migrate new <slug>); this copy is installed"
    file="$repo_root/sdata/migrations/$(date +%s)-$slug.sh"
    [[ ! -e "$file" ]] || die "$file exists already"
    cat > "$file" <<'SKELETON'
# shellcheck shell=bash
# <what per-user state this repairs, and why a packaged-default change could not>
#
# Runs as the user under `bash -euo pipefail`, once per user (the marker is this
# filename), and must be safe to run twice: check state before changing it.
# See docs/agents/migrations.md.
SKELETON
    chmod 644 "$file"
    printf '%s\n' "$file"
}
