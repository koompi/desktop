# shellcheck shell=bash
# Sourced by ./setup. Removes exactly the files the manifest says were
# installed, then the empty directories left behind. Packages are left alone:
# the installer cannot know which of them the user wanted anyway, and removing
# a shared library on a rolling distro is how you lose a login session.

# Remove the directory skeleton the install left behind, deepest first, walking
# up towards $HOME and stopping the moment a directory still holds something.
# rmdir rather than rm -r, so a directory the user put their own files in stays.
prune_empty_dirs() {
    local path dir
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        dir="$path"
        [[ -d "$dir" ]] || dir="$(dirname "$path")"
        while [[ "$dir" == "$HOME"/* ]]; do
            [[ -d "$dir" ]] || { dir="$(dirname "$dir")"; continue; }
            [[ "$DRY_RUN" == true ]] && break
            rmdir "$dir" 2>/dev/null || break
            dir="$(dirname "$dir")"
        done
    done < <(sort -r "$MANIFEST")
}

run_uninstall() {
    step "Uninstalling the KOOMPI desktop files"

    [[ -f "$MANIFEST" ]] || die "no manifest at $MANIFEST; nothing to uninstall (was this installed with ./setup?)"

    local total
    total="$(wc -l < "$MANIFEST")"
    info "$total path(s) recorded"
    confirm "Remove them from \$HOME?" || die "aborted"

    local path removed=0
    # Files first, then directories deepest-first, so a directory is only
    # removed once its contents are gone.
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ "$path" == "$HOME"/* ]] || { warn "refusing to touch $path (outside \$HOME)"; continue; }
        if [[ -f "$path" || -L "$path" ]]; then
            [[ "$DRY_RUN" == true ]] || rm -f "$path"
            removed=$((removed + 1))
        fi
    done < "$MANIFEST"

    prune_empty_dirs

    ok "removed $removed file(s)"

    if [[ -d "$VENV_DIR" ]] && confirm "Also remove the Python venv at $VENV_DIR?"; then
        run rm -rf "$VENV_DIR"
    fi

    if [[ -f "$SYSTEM_MANIFEST" ]] && confirm "Also remove the system KOOMPI login-session registration?"; then
        local system_path
        while IFS= read -r system_path; do
            case "$system_path" in
                /usr/local/bin/koompi-session|/usr/share/wayland-sessions/koompi.desktop)
                    run sudo rm -f "$system_path"
                    ;;
                *) warn "refusing unexpected system path: $system_path" ;;
            esac
        done < "$SYSTEM_MANIFEST"
        [[ "$DRY_RUN" == true ]] || rm -f "$SYSTEM_MANIFEST"
    fi

    if [[ "$DRY_RUN" != true ]]; then
        rm -f "$MANIFEST"
        rmdir "$KOOMPI_STATE_DIR" 2>/dev/null || true
    fi

    printf '\n'
    info "Backups of your pre-install config are still under ${BACKUP_ROOT}"
    info "Packages were not removed. See docs/dependencies.md for the list."
}
