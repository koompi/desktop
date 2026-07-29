# KOOMPI Session Audit

Generated for Milestone 1 of KOOMPI Desktop Experience.

## Session contract

KOOMPI core session is:

```text
Hyprland + Quickshell + KOOMPI config/services + systemd --user
```

GTK/Qt compatibility is allowed for applications. KDE/GNOME desktop infrastructure is not a required part of the core session.

## Current startup classification

### Core KOOMPI session

- `qs -c $qsConfig` — Quickshell KOOMPI shell.
- `hypridle` — idle, lock, suspend flow.
- `dbus-update-activation-environment --all` — exports session environment.
- `dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP` — keeps systemd user services aware of Wayland session.
- `dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP HYPRLAND_INSTANCE_SIGNATURE && systemctl --user start hyprland-session.target` — starts Hyprland graphical session target and supports portals.
- `hyprctl setcursor Bibata-Modern-Classic 24` — cursor setup.
- `~/.config/hypr/hyprland/scripts/scratchpad_clickaway.sh` — KOOMPI scratchpad UX support.

### KOOMPI shell feature support

- `~/.config/hypr/hyprland/scripts/start_geoclue_agent.sh` — location/geoclue support for shell features.
- `~/.config/hypr/custom/scripts/__restore_video_wallpaper.sh` — preserves current wallpaper/video wallpaper behavior.
- `wl-paste --type text --watch ... cliphist ...` — clipboard history integration.
- `wl-paste --type image --watch ... cliphist ...` — clipboard image history integration.

### Compatibility services

- `gnome-keyring-daemon --start --components=secrets` — temporary Secret Service compatibility for apps. This is not GNOME Shell/GNOME Session. Replace later only after a tested alternative exists.
- GTK app menu environment in `custom/env.lua` — compatibility for GTK apps/global menu.
- Qt/KDE-related environment in `hyprland/env.lua` — currently left unchanged to avoid breaking Qt app styling before KOOMPI has its own Qt compatibility path.

### Optional app integrations, not core DE

- `kdeconnect-indicator` — disabled from KOOMPI core autostart. It can be launched manually if the user wants KDE Connect as an app integration.
- `kdeconnectd` — disabled from XDG autostart for the KOOMPI session with a user-level override at `~/.config/autostart/org.kde.kdeconnect.daemon.desktop`.
- `wayvnc-tailscale.sh` — optional remote desktop integration bound to Tailscale. Kept for now because it is not KDE/GNOME desktop infrastructure.

### Legacy/non-KOOMPI core references to revisit later

- `QT_QPA_PLATFORMTHEME=kde` in `hyprland/env.lua`.
- `XDG_MENU_PREFIX=plasma-` in `hyprland/env.lua`.
- KDE/GNOME fallback apps in `hyprland/variables.lua` and `~/.config/koompi/config.json` app commands.
- KDE-specific window rules for portal/KDE helper windows in `hyprland/rules.lua`.

These should be migrated after KOOMPI has a stable Settings/Qt compatibility path. They are not changed in Milestone 1 to avoid unnecessary UX regressions.

## Milestone 1 changes applied

- Disabled `kdeconnect-indicator` autostart in `~/.config/hypr/custom/execs.lua`.
- Disabled `kdeconnectd` XDG autostart for KOOMPI with `~/.config/autostart/org.kde.kdeconnect.daemon.desktop`.
- Changed preferred XDG desktop portal file chooser from `kde` to `gtk` in `~/.config/xdg-desktop-portal/hyprland-portals.conf` while keeping default portal order `hyprland;gtk`.

## Notes

- Existing running `kdeconnectd` / `kdeconnect-indicator` processes may continue until logout or manual stop. The change prevents KOOMPI from starting the indicator as a core session component on next session start.
- `xdg-desktop-portal-hyprland` and `xdg-desktop-portal-gtk` are installed as portal backends.
