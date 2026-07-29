# KOOMPI Appearance System Audit

Milestone 4: Appearance system.

## Goal

KOOMPI Desktop Experience should have a coherent appearance system for:

```text
Quickshell shell UI
Hyprland compositor colors
Hyprlock / lock UI
GTK apps
Qt apps
launcher / fuzzel
terminal colors
wallpaper state
```

This milestone is an initial audit and direction-setting pass. It intentionally preserves the current global wallpaper and matugen behavior until a KOOMPI-owned theme engine can replace it safely.

## Current source of truth

Primary KOOMPI desktop settings live in:

```text
~/.config/koompi/config.json
```

Appearance-related keys currently include:

```json
appearance.fonts
appearance.palette
appearance.transparency
appearance.wallpaperTheming
background.wallpaperPath
background.thumbnailPath
background.workspaceWallpapers
background.parallax
light.night
light.antiFlashbang
wallpaperSelector
```

Current global wallpaper path at audit time:

```text
/home/userx/Pictures/Wallpapers/random_wallpaper.jpg
```

Workspace wallpapers are present in config but disabled:

```json
"background.workspaceWallpapers.enabled": false
```

## Current theme/wallpaper flow

### User-facing wallpaper flow

The current wallpaper UX is handled by Quickshell:

```text
Wallpaper selector / random wallpaper action
        ↓
~/.config/quickshell/koompi/scripts/colors/switchwall.sh
        ↓
~/.config/koompi/config.json background.wallpaperPath
        ↓
matugen templates and generated theme files
        ↓
Quickshell / Hyprland / Hyprlock / GTK / fuzzel / terminal outputs
```

The desktop background itself is rendered by Quickshell, not by KDE/GNOME wallpaper services, `swww`, or `hyprpaper`.

Important files:

```text
~/.config/koompi/config.json
~/.config/quickshell/koompi/modules/common/Config.qml
~/.config/quickshell/koompi/modules/koompi/background/Background.qml
~/.config/quickshell/koompi/modules/koompi/wallpaperSelector/
~/.config/quickshell/koompi/scripts/colors/switchwall.sh
~/.config/quickshell/koompi/scripts/colors/applycolor.sh
~/.config/matugen/config.toml
~/.config/matugen/templates/
```

### Current matugen outputs

`~/.config/matugen/config.toml` currently writes:

```text
~/.local/state/quickshell/user/generated/colors.json
~/.config/hypr/hyprland/colors.lua
~/.config/hypr/hyprlock/colors.conf
~/.config/fuzzel/fuzzel_theme.ini
~/.config/gtk-3.0/gtk.css
~/.config/gtk-4.0/gtk.css
~/.local/state/quickshell/user/generated/color.txt
~/.local/state/quickshell/user/generated/wallpaper/path.txt
```

These files are generated outputs, not the long-term source of truth.

### Current app compatibility outputs

GTK compatibility currently uses generated CSS:

```text
~/.config/gtk-3.0/gtk.css
~/.config/gtk-4.0/gtk.css
```

Fuzzel compatibility uses:

```text
~/.config/fuzzel/fuzzel_theme.ini
```

Hyprland colors use:

```text
~/.config/hypr/hyprland/colors.lua
```

Hyprlock colors and background image use:

```text
~/.config/hypr/hyprlock/colors.conf
```

Terminal colors are generated under:

```text
~/.local/state/quickshell/user/generated/terminal/
```

## Current risks

### KDE Material You coupling

`switchwall.sh` currently contains `handle_kde_material_you_colors`, which invokes KDE Material You color handling when Qt app theming is enabled.

For KOOMPI Desktop Experience, this should eventually become an internal KOOMPI theme output path, not KDE as the public/core theme architecture.

Do not remove it yet because current Qt app appearance may depend on it.

### GNOME/gsettings coupling

`switchwall.sh` currently writes GNOME/GTK compatibility through `gsettings`, for example color-scheme and GTK theme preferences.

This is acceptable as compatibility output for GTK/libadwaita apps, but KOOMPI should not treat GNOME settings as source of truth.

### Theme changes are broad

A current global wallpaper change can trigger many outputs:

```text
shell colors
Hyprland colors
Hyprlock colors
GTK colors
fuzzel colors
terminal colors
Qt/KDE Material You compatibility
```

This is acceptable for explicit global theme/wallpaper changes, but it must not happen implicitly for per-workspace wallpaper changes.

## KOOMPI theme direction

Long-term public concept:

```text
koompi-theme
```

`koompi-theme` should read KOOMPI config and apply/generate appearance outputs.

Planned direction:

```text
~/.config/koompi/config.json
        ↓
koompi-theme
        ↓
Quickshell generated colors
Hyprland generated colors
Hyprlock / lock UI colors
GTK compatibility files
Qt compatibility files
launcher/fuzzel colors
terminal colors
wallpaper metadata
```

Important rule:

```text
KOOMPI config is source of truth.
GTK/Qt/GNOME/KDE files are compatibility outputs.
```

Matugen may remain an implementation detail, but the public architecture should be KOOMPI-owned.

## Workspace wallpaper rule

Workspace wallpapers are a small Appearance sub-feature.

They must not trigger global theme regeneration by default.

First implementation rule:

```text
workspace wallpaper change -> Quickshell background path only
```

Not:

```text
workspace wallpaper change -> matugen -> GTK/Qt/Hyprland/fuzzel/terminal theme changes
```

This preserves UX stability and avoids surprising users with colors changing whenever they switch workspaces.

## Initial Milestone 4 decision

Initial Milestone 4 is documentation/config-neutral only:

- Preserve current global wallpaper behavior.
- Preserve current matugen/global theme behavior.
- Do not disable current KDE/Qt compatibility path yet.
- Do not remove gsettings compatibility writes yet.
- Do not introduce `koompi-theme` implementation yet.
- Document that `koompi-theme` is the long-term direction.
- Keep workspace wallpapers as a small opt-in sub-feature under Appearance.

## Future implementation steps

1. Add `theme` or `appearance.theme` schema only after the desired model is clear.
2. Create `koompi-theme` as a wrapper around current matugen flow first, not a rewrite.
3. Move KDE Material You handling behind a KOOMPI-named Qt compatibility output.
4. Move GNOME/gsettings writes behind a KOOMPI-named GTK compatibility output.
5. Add settings UI only after the model is stable.
6. Keep current UI design and UX unless a specific improvement is clearly better.
