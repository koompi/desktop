-- put former exec-once commands inside the func and former exec commands outside
hl.on("hyprland.start", function ()

    -- Bar, wallpaper
    hl.exec_cmd("$HOME/.config/hypr/hyprland/scripts/start_geoclue_agent.sh")
    -- The shell draws through layer-shell, which XWayland has no notion of, so
    -- it opts out of the session-wide xcb default that the global menu needs.
    hl.exec_cmd("env QT_QPA_PLATFORM=wayland qs -c $qsConfig")
    hl.exec_cmd("$HOME/.config/hypr/custom/scripts/__restore_video_wallpaper.sh")

    -- Core components (authentication, lock screen, notification daemon)
    -- gnome-keyring is started by PAM at login and by its systemd user socket,
    -- so starting it a third time here only duplicated work.
    hl.exec_cmd("hypridle")
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
    hl.exec_cmd("hyprctl setcursor Bibata-Modern-Classic 24")
end)
