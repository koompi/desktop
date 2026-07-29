# KOOMPI Config Ownership Model

Milestone 3: KOOMPI config as source of truth.

## Goal

`~/.config/koompi/config.json` is the source of truth for KOOMPI Desktop Experience behavior.

The shell, scripts, future settings UI, and compatibility generators should read KOOMPI settings from this file or from documented KOOMPI-owned config files. GNOME/KDE settings may be written as app compatibility outputs, but they should not become the source of truth for KOOMPI desktop behavior.

## Directory ownership

### User configuration: `~/.config/koompi`

Use for persistent user choices that should survive reboot, cache cleanup, and app restarts.

Current and future examples:

```text
~/.config/koompi/config.json                  primary KOOMPI settings
~/.config/koompi/actions/                     user action scripts/config
~/.config/koompi/translations/                user/project translation overrides
~/.config/koompi/wallpapers/library/          user-managed wallpaper library
~/.config/koompi/wallpapers/static/           optional static wallpaper choices
~/.config/koompi/config-ownership.md          this ownership model
~/.config/koompi/session-audit.md             milestone/session audit docs
~/.config/koompi/shell-ux-audit.md            shell UX audit docs
```

Notes:

- `config.json` is canonical for desktop settings.
- User-selected assets such as wallpaper libraries may live in `~/.config/koompi` because they are part of the user's desktop identity/config, not disposable cache.
- Existing backups under `~/.config/koompi/backups` are acceptable during this migration phase. Long-term, backups can move to state if they become automated/noisy.

### Runtime state: `~/.local/state/koompi`

Use for persistent runtime state that is not user-authored configuration.

Future examples:

```text
~/.local/state/koompi/states.json             KOOMPI shell runtime state, future target
~/.local/state/koompi/todo.json               user runtime shell todo state, future target if migrated
~/.local/state/koompi/ai/chats/               AI chat state, future target if migrated
~/.local/state/koompi/wallpapers/state/       wallpaper updater run metadata
~/.local/state/koompi/logs/                   KOOMPI service logs
```

Current reality:

```text
~/.local/state/quickshell/states.json
~/.local/state/quickshell/user/todo.json
~/.local/state/quickshell/user/ai/
~/.local/state/quickshell/user/generated/
```

These are currently owned by the running Quickshell implementation and should not be moved until there is a tested migration path.

### Disposable cache/generated data: `~/.cache/koompi`

Use for data that can be regenerated or safely deleted.

Future examples:

```text
~/.cache/koompi/media/favicons/
~/.cache/koompi/media/coverart/
~/.cache/koompi/media/boorus/
~/.cache/koompi/media/latex/
~/.cache/koompi/notifications/
~/.cache/koompi/qmlcache/                     only if KOOMPI owns this later
```

Current reality:

```text
~/.cache/quickshell/media/
~/.cache/quickshell/notifications/
~/.cache/quickshell/qmlcache/
```

These are currently Quickshell-specific and should not be moved during Milestone 3.

### Shell implementation: `~/.config/quickshell/koompi`

Use for the Quickshell implementation code and bundled assets, not as the primary user settings location.

Examples:

```text
~/.config/quickshell/koompi/shell.qml
~/.config/quickshell/koompi/modules/
~/.config/quickshell/koompi/services/
~/.config/quickshell/koompi/scripts/
~/.config/quickshell/koompi/assets/
```

Rules:

- Do not store user settings here if they belong in `~/.config/koompi/config.json`.
- Scripts may live here for now because this is the active development layout.
- Packaged KOOMPI Desktop Experience can later move implementation files to a package-owned path such as `/usr/share/koompi` or `/usr/share/koompi-desktop` while keeping user config in `~/.config/koompi`.

## Compatibility outputs are not source of truth

KOOMPI may write compatibility settings for apps, but those outputs should be derived from KOOMPI config.

Compatibility outputs include:

```text
~/.config/gtk-3.0/settings.ini
~/.config/gtk-4.0/settings.ini
~/.config/Kvantum/
~/.config/qt5ct/
~/.config/qt6ct/
~/.config/xdg-desktop-portal/hyprland-portals.conf
Hyprland generated color files
launcher/theme generated files
terminal generated theme files
```

Do not design KOOMPI settings around reading GNOME/KDE settings as the source of truth.

## Current audit summary

Observed current paths:

```text
~/.config/koompi/config.json                  exists; primary config
~/.config/koompi/actions/                     exists
~/.config/koompi/translations/                exists
~/.config/koompi/wallpapers/                 exists; new wallpaper feature structure
~/.local/state/koompi                         created as future KOOMPI runtime state root
~/.cache/koompi                               created as future KOOMPI cache root
~/.local/state/quickshell                     currently active shell state root
~/.cache/quickshell                           currently active shell cache root
~/.config/quickshell/koompi                   current shell implementation root
```

Large current state:

```text
~/.local/state/quickshell                     about 330M at audit time, mostly implementation/runtime state
~/.cache/quickshell                           about 7.5M at audit time
```

## Migration rules

1. Do not move active runtime files just to make names look clean.
2. Add new KOOMPI-owned paths first.
3. Teach code to read old and new paths during a transition window.
4. Migrate data with a script only after read/write behavior is verified.
5. Keep backups before changing config or runtime state.
6. Prefer compatibility symlinks or fallback reads over hard cutovers.
7. Update this document whenever ownership changes.

## Milestone 3 decision

Initial Milestone 3 pass chooses a conservative policy:

- `~/.config/koompi/config.json` remains the canonical source of truth.
- `~/.config/koompi` remains the user config namespace.
- `~/.local/state/koompi` and `~/.cache/koompi` are created as future KOOMPI-owned roots.
- Existing `~/.local/state/quickshell` and `~/.cache/quickshell` stay in place for now.
- No runtime files are moved in this milestone.
- GTK/Qt/GNOME/KDE settings remain compatibility outputs only.
