# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. The system-wide login session entry display managers discover before login.

# pre-marker entries claim KOOMPI via DesktopNames only; skipping them strands
# the session on start-hyprland, with no ~/.local/bin on PATH and no app launch
koompi_session_entry_is_ours() {
    local entry=$1
    [[ -e "$entry" ]] || return 0
    grep -q '^X-KOOMPI-Managed=true$' "$entry" 2>/dev/null && return 0
    grep -qE '^DesktopNames=(.*;)?KOOMPI(;.*)?$' "$entry" 2>/dev/null && return 0
    return 1
}

setup_system_session() {
    step "System login session"

    # Display managers discover sessions before a user session exists, so most
    # of them do not scan ~/.local/share/wayland-sessions. Keep that user copy
    # as a fallback, but register KOOMPI system-wide for GDM, SDDM and friends.
    local launcher=/usr/local/bin/koompi-session
    local entry=/usr/share/wayland-sessions/koompi.desktop
    local launcher_src="$REPO_ROOT/dots/.local/bin/koompi-session"
    local entry_src="$REPO_ROOT/dots/.local/share/wayland-sessions/koompi.desktop"
    local install_launcher=true

    if [[ -x /usr/bin/koompi-session ]]; then
        launcher=/usr/bin/koompi-session
        install_launcher=false
        ok "packaged /usr/bin/koompi-session present"
    fi

    if $install_launcher && [[ -e "$launcher" ]] \
       && ! grep -q "koompi-session - launch the KOOMPI" "$launcher" 2>/dev/null; then
        warn "$launcher exists and is not KOOMPI-managed; not overwriting it"
        return 0
    fi
    if ! koompi_session_entry_is_ours "$entry"; then
        warn "$entry exists and is not KOOMPI-managed; not overwriting it"
        return 0
    fi

    # never written by this installer, so it can carry a local edit
    if [[ -e "$entry" ]] && ! grep -q '^X-KOOMPI-Managed=true$' "$entry" 2>/dev/null; then
        warn "upgrading $entry from an older KOOMPI installer"
        run sudo cp -a "$entry" "$entry.pre-koompi-managed"
    fi

    local staged_entry
    staged_entry="$(mktemp)"
    sed "s|^Exec=/usr/bin/koompi-session$|Exec=${launcher}|" "$entry_src" > "$staged_entry"

    if $install_launcher; then
        run sudo install -Dm755 "$launcher_src" "$launcher"
    fi
    run sudo install -Dm644 "$staged_entry" "$entry"
    rm -f "$staged_entry"

    # SDDM is pointed at /usr/share/koompi/wayland-sessions so that plasma's and
    # hyprland's own entries never reach the greeter. Link ours into it, or the
    # greeter has nothing to offer. Harmless where SDDM is not the display
    # manager - every other DM still reads $entry.
    local dm_entry=/usr/share/koompi/wayland-sessions/koompi.desktop
    run sudo install -dm755 "$(dirname "$dm_entry")"
    run sudo ln -sfn "$entry" "$dm_entry"
    if [[ -d /etc/sddm.conf.d ]]; then
        run sudo install -Dm644 \
            "$REPO_ROOT/sdata/dist-arch/koompi-session/sddm-sessiondir.conf" \
            /etc/sddm.conf.d/20-koompi-session.conf
    fi

    if [[ "$DRY_RUN" != true && -x "$launcher" && -f "$entry" ]]; then
        mkdir -p "$(dirname "$SYSTEM_MANIFEST")"
        # The drop-in and the link go in the manifest too. Uninstalling the
        # entry while SDDM still reads only the koompi directory would leave a
        # greeter with no session to offer at all.
        if $install_launcher; then
            printf '%s\n%s\n' "$launcher" "$entry" > "$SYSTEM_MANIFEST"
        else
            printf '%s\n' "$entry" > "$SYSTEM_MANIFEST"
        fi
        printf '%s\n' "$dm_entry" >> "$SYSTEM_MANIFEST"
        [[ -f /etc/sddm.conf.d/20-koompi-session.conf ]] \
            && printf '%s\n' /etc/sddm.conf.d/20-koompi-session.conf >> "$SYSTEM_MANIFEST"
        ok "KOOMPI is registered alongside the host desktop"
    fi
}
