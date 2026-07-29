# shellcheck shell=bash
# Sourced by ./setup. Copies dots/ into $HOME.
#
# Three classes of destination, deliberately handled differently:
#   sync      - tree owned by this repo; rsync --delete so a file we removed
#               upstream also leaves the user's copy (hypr/hyprland, quickshell)
#   merge     - tree the user shares with us; copy in, never delete
#   keep      - user override slots; written only when absent, never clobbered
#
# Everything written is appended to the manifest so `setup uninstall` removes
# exactly what was added and nothing else.

# Files under dots/.config/hypr/custom are the documented place for personal
# overrides. Shipping them is how the user learns they exist; overwriting them
# on the next update would throw away their config. The terminal config is the
# same kind of slot: KOOMPI has opinions worth shipping to someone who has none,
# but a user who already configured their terminal would not thank us for
# replacing it on every update.
readonly KEEP_PATHS=(
    ".config/hypr/custom/env.lua"
    ".config/hypr/custom/execs.lua"
    ".config/hypr/custom/general.lua"
    ".config/hypr/custom/keybinds.lua"
    ".config/hypr/custom/rules.lua"
    ".config/hypr/custom/variables.lua"
    ".config/wezterm/wezterm.lua"
)

# Repo-owned: safe to mirror exactly, including deletions.
readonly SYNC_DIRS=(
    ".config/hypr/hyprland"
    ".config/hypr/hyprlock"
    ".config/quickshell/koompi"
    ".config/quickshell/koompi-quicklook"
)

# Copy aside every path in $HOME that this install is about to *change*.
# Driven off the contents of dots/, so it can never miss a file we install and
# never hoards files we do not touch.
#
# The comparison is what keeps re-running this cheap. Without it an update that
# changes three files still copies the whole thousand-file tree into a fresh
# timestamped directory, and a user who runs the installer a few times ends up
# with several gigabytes of identical backups. A file that already matches what
# we are about to write cannot be lost by writing it, so it needs no copy.
backup_existing() {
    local backup_dir count=0 skipped=0 rel target source keep
    backup_dir="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"

    while IFS= read -r -d '' rel; do
        target="$HOME/$rel"
        [[ -e "$target" || -L "$target" ]] || continue

        # Override slots are preserved rather than written, so there is nothing
        # to protect them from.
        for keep in "${KEEP_PATHS[@]}"; do
            [[ "$rel" == "$keep" ]] && continue 2
        done

        source="$REPO_ROOT/dots/$rel"
        if cmp -s -- "$source" "$target"; then
            skipped=$((skipped + 1))
            continue
        fi

        if [[ "$DRY_RUN" != true ]]; then
            mkdir -p "$backup_dir/$(dirname "$rel")"
            cp -a "$target" "$backup_dir/$rel" || { err "backup failed for ~/$rel"; return 1; }
        fi
        count=$((count + 1))
    done < <(cd "$REPO_ROOT/dots" && find . \( -type f -o -type l \) -printf '%P\0')

    if (( count > 0 )); then
        ok "backed up ${count} file(s) this run will change, to ${backup_dir}"
        (( skipped > 0 )) && info "${skipped} already matched and needed no copy"
    elif (( skipped > 0 )); then
        ok "config already matches; nothing to back up"
    else
        info "nothing to back up (no KOOMPI config present yet)"
    fi
}

# rsync, recording every path it actually wrote into the manifest.
sync_tree() {
    local src="$1" dest="$2"
    shift 2
    run mkdir -p "$dest"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s     $ rsync -a %s %s/ %s/%s\n' "${C_DIM}" "$*" "$src" "$dest" "${C_RST}"
        return 0
    fi
    local rel
    while IFS= read -r rel; do
        [[ -n "$rel" && "$rel" != "./" ]] || continue
        manifest_add "${dest%/}/${rel%/}"
    done < <(rsync -a "$@" --out-format='%n' "$src"/ "$dest"/)
}

install_files() {
    step "Installing config files"

    local d
    for d in "$XDG_BIN_HOME" "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_STATE_HOME"; do
        [[ -d "$d" ]] || run mkdir -p "$d"
    done

    if [[ "$SKIP_BACKUP" != true ]]; then
        backup_existing
    else
        warn "--no-backup given; existing config will be overwritten with no copy kept"
    fi

    # Pull in the rounded-polygon submodule; the shell fails to load without it.
    if [[ -f "$REPO_ROOT/.gitmodules" ]] && ! [[ -e "$REPO_ROOT/dots/.config/quickshell/koompi/modules/common/widgets/shapes/qmldir" ]]; then
        run git -C "$REPO_ROOT" submodule update --init --recursive
    fi

    # Preserve user override slots across the sync by staging a copy of dots/
    # with the already-present ones removed.
    local stage
    stage="$(mktemp -d)"
    run cp -a "$REPO_ROOT/dots/." "$stage/"
    local rel
    for rel in "${KEEP_PATHS[@]}"; do
        if [[ -e "$HOME/$rel" ]]; then
            info "keeping your $rel"
            run rm -f "$stage/$rel"
        fi
    done

    # Build artefacts and caches must never reach $HOME.
    local -a excludes=(
        --exclude='.git' --exclude='.gitignore' --exclude='.claude'
        --exclude='zig-out' --exclude='.zig-cache' --exclude='__pycache__'
        --exclude='*.pyc' --exclude='.qmlls.ini'
    )

    for rel in "${SYNC_DIRS[@]}"; do
        [[ -d "$stage/$rel" ]] || continue
        info "sync  ~/$rel"
        sync_tree "$stage/$rel" "$HOME/$rel" --delete "${excludes[@]}"
        run rm -rf "$stage/$rel"
    done

    info "merge ~/.config"
    sync_tree "$stage/.config" "$XDG_CONFIG_HOME" "${excludes[@]}"
    info "merge ~/.local/share"
    sync_tree "$stage/.local/share" "$XDG_DATA_HOME" "${excludes[@]}"
    info "merge ~/.local/bin"
    sync_tree "$stage/.local/bin" "$XDG_BIN_HOME" "${excludes[@]}"

    run rm -rf "$stage"

    install_session_entry
    manifest_finalize
    ok "config files installed"
}

# The shipped koompi.desktop points at /usr/bin/koompi-session, which is where
# the Arch package puts it. A user-level install has no such file, so the Exec
# is rewritten to the copy that actually exists. Display managers need an
# absolute path here; $HOME is not expanded in a desktop entry's Exec.
install_session_entry() {
    local entry="${XDG_DATA_HOME}/wayland-sessions/koompi.desktop"
    [[ -f "$entry" ]] || return 0
    if [[ -x /usr/bin/koompi-session ]]; then
        info "system koompi-session present, leaving session entry pointing at it"
        return 0
    fi
    info "pointing the session entry at ${XDG_BIN_HOME}/koompi-session"
    if [[ "$DRY_RUN" == true ]]; then return 0; fi
    local tmp
    tmp="$(mktemp)"
    sed "s|^Exec=/usr/bin/koompi-session$|Exec=${XDG_BIN_HOME}/koompi-session|" "$entry" > "$tmp"
    grep -q "^Exec=${XDG_BIN_HOME}/koompi-session$" "$tmp" \
        || { rm -f "$tmp"; die "failed to rewrite Exec= in $entry"; }
    mv -f "$tmp" "$entry"
    chmod 644 "$entry"
}
