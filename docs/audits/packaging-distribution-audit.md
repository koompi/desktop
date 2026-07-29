# KOOMPI Packaging and Distribution Audit

Milestone 7: Packaging and distribution.

## Goal

KOOMPI Desktop Experience should eventually be installable as a real Wayland desktop session while preserving user overrides and avoiding disruptive moves during development.

This milestone is documentation and packaging-direction only. No active Hyprland, Quickshell, systemd, portal, wallpaper, theme, or settings files are moved.

## Current development layout

Current active user/development paths:

```text
~/.config/hypr/                         active Hyprland config
~/.config/hypr/hyprland.lua             active Hyprland Lua entrypoint
~/.config/hypr/hyprland/                active base Hyprland modules
~/.config/hypr/custom/                  user/custom Hypr overrides
~/.config/quickshell/koompi/            active Quickshell KOOMPI shell implementation
~/.config/koompi/config.json            KOOMPI user config source of truth
~/.config/koompi/                       KOOMPI user config/docs/audits/wallpapers
~/.local/state/koompi/                  future KOOMPI runtime state root
~/.cache/koompi/                        future KOOMPI cache root
~/.config/systemd/user/                 current user services/targets
~/.config/xdg-desktop-portal/           current portal preference config
```

Current active session is launched by the user's existing Hyprland setup, not by a packaged KOOMPI session file yet.

No active session file was found under:

```text
/usr/share/wayland-sessions
/usr/local/share/wayland-sessions
~/.local/share/wayland-sessions
```

## Runtime dependencies observed

Core runtime commands currently expected by the KOOMPI session:

```text
Hyprland
hyprctl
qs / quickshell
systemctl --user
dbus-update-activation-environment
hypridle
hyprlock
matugen
fuzzel
wl-paste
cliphist
gnome-keyring-daemon          temporary Secret Service compatibility
```

Runtime processes verified during audit:

```text
qs -c koompi
hypridle
xdg-desktop-portal
xdg-desktop-portal-hyprland
xdg-desktop-portal-gtk
```

Optional/feature dependencies currently referenced:

```text
easyeffects                  audio effects service, currently unavailable in PATH during audit
wayvnc                       optional remote desktop integration
Tailscale                    optional network binding for wayvnc helper
geoclue                      shell/location support
ImageMagick / magick         image/wallpaper metadata helpers
jq                           config/script manipulation
python3                      helper scripts
node                         unrelated/openclaw services, not KOOMPI core
```

## Package naming

Internal package/session command names should use `koompi`.

Recommended packages/components:

```text
koompi-session       session launcher and wayland session file
koompi-shell         Quickshell shell implementation/assets
koompi-hyprland      Hyprland defaults/modules
koompi-settings      settings/control center entrypoint
koompi-theme         appearance/theme helper
koompi-wallpaper     wallpaper helper
koompi-health        diagnostics helper
```

A single meta-package can later depend on these:

```text
koompi-desktop-experience
```

User-facing name:

```text
KOOMPI Desktop Experience
```

## Future package-owned paths

When packaged, defaults should move out of user config into package-owned locations.

Potential package paths:

```text
/usr/share/koompi/hypr/                    packaged Hyprland defaults
/usr/share/koompi/quickshell/              packaged Quickshell shell
/usr/share/koompi/assets/                  branding/assets
/usr/share/koompi/defaults/                default config templates
/usr/share/koompi/systemd/user/            user unit templates
/usr/share/koompi/xdg-desktop-portal/      portal config templates
/usr/bin/koompi-session                    session launcher
/usr/bin/koompi-settings                   settings launcher
/usr/bin/koompi-theme                      theme helper
/usr/bin/koompi-wallpaper                  wallpaper helper
/usr/bin/koompi-health                     diagnostics helper
/usr/share/wayland-sessions/koompi.desktop session file
```

User-owned paths should remain:

```text
~/.config/koompi/                          user KOOMPI config and user-owned assets
~/.local/state/koompi/                     runtime state
~/.cache/koompi/                           disposable cache
~/.config/hypr/custom/                     user Hyprland overrides during transition
```

## Future session file

Target file:

```text
/usr/share/wayland-sessions/koompi.desktop
```

Target content:

```ini
[Desktop Entry]
Name=KOOMPI
Comment=KOOMPI Desktop Experience, powered by Hyprland
Exec=koompi-session
Type=Application
DesktopNames=KOOMPI;Hyprland
```

This file was **not installed** during Milestone 7. A non-active draft may live under `~/.config/koompi/packaging/` for reference.

## Future session launcher contract

Target command:

```text
koompi-session
```

Responsibilities:

1. Export/normalize session environment.
2. Select KOOMPI Hyprland config/defaults.
3. Preserve user overrides.
4. Start Hyprland.
5. Ensure `XDG_CURRENT_DESKTOP` / `DesktopNames` expose KOOMPI and Hyprland appropriately.
6. Avoid starting KDE/GNOME desktop infrastructure.

Initial sketch:

```bash
#!/usr/bin/env bash
set -euo pipefail

export XDG_CURRENT_DESKTOP="KOOMPI:Hyprland"
export XDG_SESSION_DESKTOP="KOOMPI"
export XDG_SESSION_TYPE="wayland"

exec Hyprland --config "$HOME/.config/hypr/hyprland.lua"
```

Do not deploy this until tested. Current active session must remain untouched.

## Migration strategy

Packaging should not overwrite the user's current working setup.

Recommended migration phases:

### Phase P1: Package defaults only

- Install package defaults under `/usr/share/koompi`.
- Keep user config untouched.
- Provide `koompi-health` to report missing dependencies and config status.

### Phase P2: Session entrypoint

- Install `koompi-session` and `koompi.desktop`.
- Let user choose KOOMPI from display manager.
- Do not remove existing Hyprland session.

### Phase P3: Config migration assistant

- Provide a migration script that can copy or merge known settings.
- Back up before writing.
- Support dry-run.
- Preserve `~/.config/koompi/config.json` as the user's source of truth.

### Phase P4: Split packaged defaults and user overrides

- Move base shell/Hyrpland defaults to package path.
- Keep user overrides in `~/.config/koompi` and `~/.config/hypr/custom` or a future KOOMPI override path.
- Add fallback search paths so existing configs continue to work during transition.

## Optional compatibility packages

GTK/Qt app compatibility should remain supported without making GNOME/KDE core.

Potential optional dependencies:

```text
gtk theme support
qt5ct / qt6ct or future KOOMPI Qt compatibility path
Kvantum if selected
xdg-desktop-portal-gtk for GTK file chooser compatibility
Secret Service provider, currently gnome-keyring-daemon
```

KDE/GNOME apps may be installed as applications, but not as required DE infrastructure.

## Packaging risks

- Moving active Quickshell files too early can break the shell.
- Moving Hyprland configs too early can break login/session startup.
- Installing a session file before `koompi-session` is tested can create a broken login option.
- Treating KDE/GNOME compatibility as core would undermine the KOOMPI DE direction.
- Changing `XDG_CURRENT_DESKTOP` may affect portals and app behavior; test carefully.

## Initial Milestone 7 decision

Milestone 7 initial pass is complete when:

- Current package/session-like files are audited.
- Future package paths are documented.
- Future session file and launcher contract are documented.
- Dependency and compatibility package direction is documented.
- No active configs are moved.

This milestone intentionally does not install the session file or session launcher.
