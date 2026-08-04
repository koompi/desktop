# shellcheck shell=bash
# Sourced by ./setup. Copies dots/ into $HOME.
#
# Three classes of destination:
#   sync   - tree owned by this repo; rsync --delete, so a file removed upstream
#            also leaves the user's copy (hypr/hyprland, quickshell)
#   merge  - tree shared with the user; copy in, never delete
#   keep   - user override slots; written only when absent, never clobbered
#
# Everything written is appended to the manifest, so `setup uninstall` removes
# exactly what was added.

# Override slots. Shipping them is how the user learns they exist; rewriting them on
# the next update throws away their config. The EasyEffects db is state the app
# rewrites on every quit, so it is seeded once - writing it again reverts whatever
# chain the user built and resets their device selection.
readonly KEEP_PATHS=(
    ".config/easyeffects/db/easyeffectsrc"
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

# Older configs could persist both workspace flags as true, and the bar's number
# branch wins that conflict, so app icons disappear even after a corrected default
# ships. Fix the legacy state once, then leave the setting user-owned.
migrate_workspace_app_icons() {
    local config="${XDG_CONFIG_HOME}/koompi/config.json"
    local marker="${KOOMPI_STATE_DIR}/migrations/workspace-app-icons-v1"

    [[ -e "$marker" ]] && return 0

    if [[ ! -e "$config" ]]; then
        info "new config will use workspace app icons"
        if [[ "$DRY_RUN" != true ]]; then
            mkdir -p "$(dirname "$marker")"
            : > "$marker"
        fi
        return 0
    fi

    if ! have jq; then
        warn "jq is unavailable; cannot check the legacy workspace icon setting"
        return 0
    fi
    if ! jq -e . "$config" >/dev/null 2>&1; then
        warn "$config is not valid JSON; leaving it untouched"
        return 0
    fi

    if jq -e '
        .bar.workspaces.showAppIcons == true
        and .bar.workspaces.alwaysShowNumbers == true
    ' "$config" >/dev/null; then
        info "migrating the legacy workspace-number setting so app icons remain visible"
        if [[ "$DRY_RUN" == true ]]; then
            return 0
        fi

        local backup_dir tmp
        backup_dir="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir/.config/koompi"
        cp -a "$config" "$backup_dir/.config/koompi/config.json" \
            || { err "could not back up $config"; return 1; }

        tmp="$(mktemp "${config}.tmp.XXXXXX")"
        if ! jq '.bar.workspaces.alwaysShowNumbers = false' "$config" > "$tmp"; then
            rm -f "$tmp"
            err "could not migrate $config"
            return 1
        fi
        chmod --reference="$config" "$tmp"
        mv -f "$tmp" "$config"
        ok "workspace app icons restored; backup saved under $backup_dir"
    fi

    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$(dirname "$marker")"
        : > "$marker"
    fi
}

# A persisted toggle array replaces the shipped default outright - Quickshell's
# JsonAdapter does not merge lists - so anyone with an existing config.json keeps
# the list they first got, however many toggles ship later. That left an install
# showing six controls on the main screen and the same six behind "All controls",
# which is the drawer's whole purpose gone. Append what is missing rather than
# overwrite: the pencil exists so people can arrange this, and an arrangement is
# theirs to keep.
migrate_quick_toggles() {
    local config="${XDG_CONFIG_HOME}/koompi/config.json"
    local marker="${KOOMPI_STATE_DIR}/migrations/quick-toggles-v1"
    local defaults="$REPO_ROOT/dots/.config/quickshell/koompi/modules/common/Config.qml"

    [[ -e "$marker" ]] && return 0

    if [[ ! -e "$config" ]]; then
        info "new config will use the full quick-toggle list"
        if [[ "$DRY_RUN" != true ]]; then
            mkdir -p "$(dirname "$marker")"
            : > "$marker"
        fi
        return 0
    fi

    if ! have jq; then
        warn "jq is unavailable; cannot check the quick-toggle list"
        return 0
    fi
    if ! jq -e 'type == "object"' "$config" >/dev/null 2>&1; then
        warn "$config is not a JSON object; leaving it untouched"
        return 0
    fi

    # Read the order out of the QML that defines it, so the two cannot drift.
    local -a shipped=()
    mapfile -t shipped < <(
        sed -n '/property list<var> toggles: \[/,/^ *\]/p' "$defaults" |
            grep -o '"type": *"[A-Za-z]*"' | sed 's/.*"\([A-Za-z]*\)"$/\1/'
    )
    (( ${#shipped[@]} )) || { warn "could not read the shipped quick-toggle list"; return 0; }

    local -a missing=()
    local type
    for type in "${shipped[@]}"; do
        jq -e --arg t "$type" '
            (.sidebar.quickToggles.android.toggles // []) | any(.type == $t)
        ' "$config" >/dev/null || missing+=("$type")
    done

    if (( ${#missing[@]} )); then
        info "adding ${#missing[@]} missing quick toggle(s): ${missing[*]}"
        if [[ "$DRY_RUN" != true ]]; then
            local backup_dir tmp
            backup_dir="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)"
            mkdir -p "$backup_dir/.config/koompi"
            cp -a "$config" "$backup_dir/.config/koompi/config.json" \
                || { err "could not back up $config"; return 1; }

            tmp="$(mktemp "${config}.tmp.XXXXXX")"
            # Size 2 throughout: a size-1 toggle draws its icon with no label, which
            # is what made an appended keep-awake read as an unlabelled block.
            if ! jq --argjson add "$(printf '%s\n' "${missing[@]}" |
                    jq -R '{size: 2, type: .}' | jq -s '.')" '
                    .sidebar.quickToggles.android.toggles =
                        ((.sidebar.quickToggles.android.toggles // []) + $add)
                ' "$config" > "$tmp"; then
                rm -f "$tmp"
                err "could not migrate $config"
                return 1
            fi
            # jq empty passes on the empty file a failed redirect leaves behind.
            if ! jq -e 'type == "object"' "$tmp" >/dev/null 2>&1; then
                rm -f "$tmp"
                err "migration produced invalid JSON; $config left untouched"
                return 1
            fi
            chmod --reference="$config" "$tmp"
            mv -f "$tmp" "$config"
            ok "quick toggles restored; backup saved under $backup_dir"
        fi
    fi

    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$(dirname "$marker")"
        : > "$marker"
    fi
}

# Copy aside every path in $HOME this install is about to change. Driven off dots/,
# so it can neither miss a file we install nor hoard files we do not touch.
#
# The comparison is what keeps re-running cheap: without it an update that changes
# three files copies the whole tree into a fresh timestamped directory. A file that
# already matches what we are about to write cannot be lost by writing it.
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

    migrate_workspace_app_icons
    migrate_quick_toggles

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

# The shipped entries point at /usr/bin/koompi-session, where the Arch package puts
# it. A user-level install has no such file, so the Exec is rewritten to the copy
# that exists. Absolute path required: $HOME is not expanded in a desktop entry.
install_session_entry() {
    install_one_session_entry koompi-session "${XDG_DATA_HOME}/wayland-sessions/koompi.desktop"
}

install_one_session_entry() {
    local launcher="$1" entry="$2"
    [[ -f "$entry" ]] || return 0
    if [[ -x "/usr/bin/$launcher" ]]; then
        info "system $launcher present, leaving session entry pointing at it"
        return 0
    fi
    info "pointing the session entry at ${XDG_BIN_HOME}/$launcher"
    if [[ "$DRY_RUN" == true ]]; then return 0; fi
    local tmp
    tmp="$(mktemp)"
    sed "s|^Exec=/usr/bin/${launcher}$|Exec=${XDG_BIN_HOME}/${launcher}|" "$entry" > "$tmp"
    grep -q "^Exec=${XDG_BIN_HOME}/${launcher}$" "$tmp" \
        || { rm -f "$tmp"; die "failed to rewrite Exec= in $entry"; }
    mv -f "$tmp" "$entry"
    chmod 644 "$entry"
}
