# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. Desktop portals, the cursor fallback and the GTK defaults pushed through gsettings.

# XDG_DESKTOP_PORTAL_DIR does not add a directory, it REPLACES every other one, so
# the old five-file whitelist made every backend outside it invisible.
# xdg-desktop-portal has searched
# ~/.local/share/xdg-desktop-portal/portals since 1.19, so koompi.portal ships there
# through dots/ and the override has nothing left to do.
setup_portals() {
    step "Desktop portals"
    systemd_running || { warn "no running systemd; skipping portal cleanup"; return 0; }

    local dropin="${XDG_CONFIG_HOME}/systemd/user/xdg-desktop-portal.service.d/koompi-remotedesktop.conf"
    if [[ -f "$dropin" ]] && grep -q 'XDG_DESKTOP_PORTAL_DIR' "$dropin"; then
        info "removing the portal directory override; it hid every backend it did not list"
        run rm -f "$dropin"
        run rmdir --ignore-fail-on-non-empty "$(dirname "$dropin")"
        warn "the old whitelist at ${XDG_DATA_HOME}/koompi/portals is now unused; left in place rather than deleted"
    fi

    systemd_user_running && run systemctl --user daemon-reload
    return 0
}

# The cursor theme KOOMPI ships. It has to be stated in four places that cannot
# read each other: hyprland/env.lua (XCURSOR_THEME), hyprland/execs.lua (hyprctl
# setcursor), gsettings for GTK, and the default-cursors fallback below. Change
# it here and in the two lua files; tests/test_cursor_theme.sh fails if they drift.
readonly KOOMPI_CURSOR_THEME='Adwaita'
readonly KOOMPI_CURSOR_SIZE=24

# The cursor of last resort, and it is reached far more often than "clients that
# set no theme". libXcursor resolves each requested name through the theme's
# Inherits chain and then through the `default` theme, so a name the session
# theme happens not to carry lands on whatever `default` points at. Adwaita ships
# 63 names and drops the legacy aliases; Qt/xcb clients ask for `pointing_hand`
# first, which Adwaita lacks. With `default` inheriting a second theme, that one
# request resolves there and Qt never falls through to the `hand2` Adwaita does
# have - so a single shape comes back in the wrong theme mid-session. Point it at
# the theme we ship. The system copy under /usr/share/icons/default belongs to
# default-cursors, so this user-level one wins without fighting pacman.
setup_cursor_default() {
    local theme_dir="$HOME/.icons/default"
    local index="$theme_dir/index.theme"
    local want="[Icon Theme]
Inherits=${KOOMPI_CURSOR_THEME}"

    if [[ -f "$index" ]] && ! grep -q '^Inherits=' "$index"; then
        warn "$index exists but sets no Inherits=; leaving it alone"
        return 0
    fi
    if [[ -f "$index" ]] && [[ "$(cat "$index")" == "$want" ]]; then
        ok "cursor fallback already points at ${KOOMPI_CURSOR_THEME}"
        return 0
    fi
    info "pointing the default cursor fallback at ${KOOMPI_CURSOR_THEME}"
    if [[ "$DRY_RUN" == true ]]; then return 0; fi
    mkdir -p "$theme_dir"
    printf '%s\n' "$want" > "$index" || { err "could not write $index"; return 1; }
    manifest_add "$index"
}

# GTK apps read their font and dark-mode preference from gsettings, not from
# ~/.config/koompi/config.json, so the defaults have to be pushed once.
setup_toolkit_defaults() {
    step "Toolkit defaults"
    if have gsettings; then
        run gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'
        run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        run gsettings set org.gnome.desktop.interface cursor-theme "$KOOMPI_CURSOR_THEME"
        run gsettings set org.gnome.desktop.interface cursor-size "$KOOMPI_CURSOR_SIZE"
    else
        warn "gsettings not found; GTK apps keep their stock font and light theme"
    fi
    setup_cursor_default
    if have fc-cache; then
        run fc-cache -f
    fi
    if have update-desktop-database; then
        try update-desktop-database "${XDG_DATA_HOME}/applications" 2>/dev/null || true
    fi
}
