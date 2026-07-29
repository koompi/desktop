# KOOMPI Core Desktop Services Audit

Milestone 6: Core desktop services.

## Goal

Replace ad-hoc glue with clear KOOMPI-owned service boundaries where helpful, without rewriting working services prematurely.

The first pass is documentation and low-risk observability groundwork only. Existing working session startup, Quickshell modules, Hyprland scripts, portals, lock/idle behavior, wallpaper/theme flow, and app compatibility are preserved.

## Desired KOOMPI service/command names

Long-term service/command boundaries:

```text
koompi-session      session bootstrap and environment contract
koompi-theme        appearance/theme application and compatibility outputs
koompi-wallpaper    global/workspace wallpaper operations
koompi-settings     settings/control center entrypoint or helper
koompi-health       diagnostics and health checks
```

Internal file/service names should use `koompi`. User-facing docs can say **KOOMPI Desktop Experience**.

## Current service/script landscape

### Hyprland startup commands

Current startup comes from:

```text
~/.config/hypr/hyprland/execs.lua
~/.config/hypr/custom/execs.lua
```

Current commands are classified as:

#### Core session

```text
qs -c $qsConfig
hypridle
dbus-update-activation-environment --all
dbus-update-activation-environment --systemd WAYLAND_DISPLAY XDG_CURRENT_DESKTOP
systemctl --user start hyprland-session.target
hyprctl setcursor Bibata-Modern-Classic 24
```

#### Shell feature support

```text
start_geoclue_agent.sh
__restore_video_wallpaper.sh
wl-paste watchers for cliphist
scratchpad_clickaway.sh
```

#### Compatibility support

```text
gnome-keyring-daemon --start --components=secrets
GTK_MODULES=appmenu-gtk-module
current Qt env compatibility
```

#### Optional integration

```text
wayvnc-tailscale.sh
```

KDE Connect was already removed from required KOOMPI core session startup.

### Quickshell scripts

Current script families:

```text
scripts/ai/                 AI helper scripts
scripts/colors/             wallpaper/theme/matugen/applycolor flow
scripts/hyprland/           Hyprland config helper
scripts/images/             wallpaper/widget image analysis helpers
scripts/keyring/            Secret Service/keyring helpers
scripts/musicRecognition/   song recognition helper
scripts/thumbnails/         thumbnail generation helpers
scripts/videos/             recording helper
```

These are currently implementation scripts, not formal KOOMPI services.

### Systemd user units

Existing user units include both KOOMPI/session-related and unrelated user services:

```text
hyprland-session.target      relevant to KOOMPI session
bidbybid-pipeline.*          unrelated project service
openclaw-gateway.service     unrelated project service
no-mistakes-daemon-*.service unrelated dev tool service
elephant.service             app/service, not currently KOOMPI core
ydotoold.service             input automation daemon, app/support service
```

Milestone 6 should not take ownership of unrelated user services.

## Current gaps

### Scripts are not consistently observable

Many scripts do not use all of:

```text
set -euo pipefail
structured log path
clear error messages
trap-based cleanup
journal/systemd integration
```

This is acceptable for interactive helpers, but unattended scripts and future timers should log clearly.

### Service boundaries are mixed

Some functions are currently direct shell startup commands. Long-term, KOOMPI should decide whether they are:

```text
session bootstrap
one-shot setup
long-running service
timer job
interactive helper
compatibility output
```

### Long-running services should be deliberate

Current direct startup runs several long-lived processes:

```text
qs
hypridle
gnome-keyring-daemon
easyeffects
wl-paste watchers
scratchpad click-away helper
wayvnc integration when enabled
```

This is not wrong, but future KOOMPI-owned daemons should be started through clear session contracts or systemd user units where appropriate.

## KOOMPI service rules

### Rule 1: prefer small commands

A `koompi-*` command should do one clear job.

Good examples:

```text
koompi-theme apply
koompi-wallpaper randomize
koompi-health check
```

Avoid large multi-purpose scripts that silently mutate many subsystems.

### Rule 2: use systemd user units for unattended jobs

Use `systemd --user` for:

```text
timers
background daemons
session-scoped services
retry/restart behavior
journal logging
```

Do not use systemd for every interactive helper.

### Rule 3: log unattended work

For future KOOMPI-owned services, prefer:

```text
~/.local/state/koompi/logs/
```

and/or systemd journal.

### Rule 4: keep compatibility explicit

GTK/Qt/Secret Service/portal outputs are compatibility layers. They should be named as such in future service code.

### Rule 5: do not rewrite working services without a migration path

Current startup works. Migrations should be staged:

1. document current behavior
2. wrap with KOOMPI command while preserving behavior
3. verify
4. move to systemd user unit only when beneficial
5. remove old path

## Low-risk groundwork applied

Created future KOOMPI service log root:

```text
~/.local/state/koompi/logs
```

No existing services were changed.

## Future service candidates

### `koompi-session`

Purpose:

```text
start KOOMPI Hyprland session, export environment, start shell/session targets
```

Possible future ownership:

```text
~/.local/bin/koompi-session
/usr/bin/koompi-session when packaged
```

Do not implement until packaging/session Milestone 7 work starts.

### `koompi-theme`

Purpose:

```text
apply KOOMPI appearance settings, generate compatibility outputs
```

Initial implementation should wrap existing matugen/switchwall behavior rather than rewrite it.

### `koompi-wallpaper`

Purpose:

```text
global wallpaper actions
workspace wallpaper randomization
hourly/wake wallpaper automation
```

Should avoid global theme regeneration for workspace-only wallpaper changes.

### `koompi-settings`

Purpose:

```text
launch settings/control center reliably
```

Could wrap:

```text
qs -p ~/.config/quickshell/koompi/settings.qml
```

### `koompi-health`

Purpose:

```text
check qs, hypridle, portals, config JSON validity, key directories, optional compatibility outputs
```

This is a good early utility because it improves debuggability without changing UX.

## Milestone 6 initial decision

Initial Milestone 6 is complete as an audit and service-boundary pass:

- Keep existing working services and startup commands.
- Do not move startup commands into new daemons yet.
- Create `~/.local/state/koompi/logs` for future KOOMPI-owned service logs.
- Document future `koompi-*` service boundaries.
- Prefer `systemd --user` only for future unattended timers/daemons.
- Do not take ownership of unrelated user services.
