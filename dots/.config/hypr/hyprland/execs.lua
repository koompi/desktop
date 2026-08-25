-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function ()

    -- Bar, wallpaper
    -- The shell draws through layer-shell, which XWayland has no notion of, so
    -- it opts out of the session-wide xcb default that the global menu needs.
    hl.exec_cmd("env QT_QPA_PLATFORM=wayland qs -c $qsConfig")
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")
    -- Swipe progress for the shell's wallpaper. Hyprland version-locks plugins,
    -- so after a Hyprland update this simply does not load until it is rebuilt
    -- and the wallpaper goes back to sliding only once the swipe commits.
    hl.exec_cmd("sh -c 'test -f /usr/lib/koompi/hyprland/koompi-swipe-progress.so && hyprctl plugin load /usr/lib/koompi/hyprland/koompi-swipe-progress.so'")

    -- Core components (authentication, lock screen, notification daemon)
    -- gnome-keyring is started by PAM at login and by its systemd user socket,
    -- so starting it a third time here only duplicated work.
    -- hypridle is the packaged user unit (WantedBy=graphical-session.target),
    -- pulled in when hyprland-session.target starts below: its log lands in
    -- the journal, it restarts on crash, and a reload cannot start a second one.
    hl.exec_cmd("dbus-update-activation-environment --all")
    hl.exec_cmd("sleep 1 && dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP") -- Some fix idk

    -- Audio
    hl.exec_cmd("sh -c 'command -v easyeffects >/dev/null && easyeffects --hide-window --service-mode'")

    -- Clipboard: history
    --hl.exec_cmd("wl-paste --watch cliphist store")
    hl.exec_cmd("wl-paste --type text --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")
    hl.exec_cmd("wl-paste --type image --watch bash -c 'cliphist store && qs -c $qsConfig ipc call cliphistService update'")

    -- Portals need an activated graphical-session.target, and the portal has to
    -- find the compositor, so import the Wayland env before starting it.
    hl.exec_cmd("dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target && systemctl --user start xdg-desktop-autostart.target")

    -- Cursor
    hl.exec_cmd("hyprctl setcursor Adwaita 24")
end)
