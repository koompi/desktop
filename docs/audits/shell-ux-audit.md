# KOOMPI Shell UX Stability/Polish Audit

Generated for Milestone 2 of KOOMPI Desktop Experience.

## Scope

Milestone 2 is not a redesign. The goal is to preserve the current KOOMPI shell layout and visual language while removing small sources of runtime instability/jank that can affect daily UX.

## Current shell structure

Active panel family:

```text
panelFamily = ii
```

Available panel families:

```text
ii
waffle
```

Current `ii` shell loads these user-facing surfaces:

```text
Background
Bar / VerticalBar
Cheatsheet
Dock when enabled
Lock
MediaControls
NotificationPopup
OnScreenDisplay
OnScreenKeyboard
Overlay
Overview
Polkit
RegionSelector
ScreenCorners
ScreenTranslator
SessionScreen
SidebarLeft
SidebarRight
WallpaperSelector
ScratchpadDismiss
```

Current IPC surface was verified with `qs -c koompi ipc show` and includes controls for:

```text
bar
cheatsheet
search/workspace overview/clipboard
mediaControls
sidebarLeft
sidebarRight
region tools
brightness
osk
screenTranslator
wallpaperSelector
theme
session
overlay
osdVolume
mpris
wallpapers
lock
```

## UX findings

### Preserved

- Current layout and visual language were not redesigned.
- Panel family remains unchanged.
- Existing Quickshell modules remain loaded.
- Existing keyboard/IPC control surface remains available.
- Current wallpaper, lock, sidebar, overview, and launcher architecture remains intact.

### Small runtime issues found in logs

Quickshell logs showed repeated warnings that can create noisy diagnostics and may indicate small unstable states:

1. `ActiveWindow.qml`: `Unable to assign [undefined] to bool`.
   - Cause: `hasWindow` bool expression could return a non-bool/undefined value through `root.biggestWindow`.
   - Fix: make the bool expression explicit and null-safe.

2. `NotificationPopup.qml`: `Cannot read property 'enable' of undefined`.
   - Cause: code referenced `Config.options.notifications.forceMonitor`, but config schema uses `Config.options.notifications.monitor`.
   - Fix: use the existing `monitor` config object.

3. `ToolbarTabBar.qml`: `Unable to assign [undefined] to QQuickItem*`.
   - Cause: active tab target could be undefined while children/current index are settling.
   - Fix: make target item nullable and guard animation indexes.

## Changes applied

Only small null-safety/config-reference fixes were applied:

```text
~/.config/quickshell/koompi/modules/koompi/bar/ActiveWindow.qml
~/.config/quickshell/koompi/modules/koompi/notificationPopup/NotificationPopup.qml
~/.config/quickshell/koompi/modules/common/widgets/ToolbarTabBar.qml
```

No visual redesign was made.

## Deferred issues

Some warnings remain intentionally deferred because they involve broader architecture or optional services:

- Duplicate IPC handler warnings when multiple panel families/fallback modules are loaded.
- Missing `/home/user/.local/bin/koompi-agent-memd`; should be handled under service/AI integration cleanup, not shell UX redesign.
- Network service null conversion warning; needs a focused networking service audit.
- Waffle-specific anchor warning; active panel family is currently `ii`, so this is lower priority unless Waffle is made primary.

## Milestone 2 status

Milestone 2 initial pass is complete as a conservative stability/polish pass:

- Current UI layout preserved.
- Runtime log noise reduced for clear small issues.
- No new UI model introduced.
- Bigger redesigns explicitly deferred.
