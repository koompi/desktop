# KOOMPI Settings / Control Center Audit

Milestone 5: Settings and control center.

## Goal

KOOMPI should be configurable without hand-editing JSON for common user-facing behavior.

The first pass is not a redesign. It documents the current settings app, preserves the current UX/component style, and fixes only one clear broken binding found during the audit.

## Current settings entrypoint

Current standalone settings app:

```text
~/.config/quickshell/koompi/settings.qml
```

Current title:

```text
KOOMPI Settings
```

Current size/defaults:

```text
minimumWidth: 750
minimumHeight: 500
width: 1100
height: 750
```

Current UX structure:

```text
ApplicationWindow
  ColumnLayout
    optional titlebar
    RowLayout
      NavigationRail
      content pane
        Loader with fade/slide page transition
```

Current style primitives:

```text
ContentPage
ContentSection
ContentSubsection
ConfigSwitch
ConfigSpinBox
ConfigSlider
ConfigSelectionArray
ConfigRow
StyledText
StyledToolTip
RippleButtonWithIcon
NavigationRail
NavigationRailButton
FloatingActionButton
MaterialSymbol
```

These should remain the default component language for KOOMPI Settings.

## Current settings pages

Current pages in `settings.qml`:

```text
Quick                  modules/settings/QuickConfig.qml
General                modules/settings/GeneralConfig.qml
Bar                    modules/settings/BarConfig.qml
Background             modules/settings/BackgroundConfig.qml
Interface              modules/settings/InterfaceConfig.qml
Services               modules/settings/ServicesConfig.qml
Advanced               modules/settings/AdvancedConfig.qml
About                  modules/settings/About.qml
```

## Roadmap target pages

The roadmap wants common-user control center coverage for:

```text
Appearance
Wallpaper
Workspace wallpapers
Displays
Keyboard shortcuts
Input
Power
Network
Bluetooth
Sound
Privacy/Portals
About
```

## Mapping from current pages to target pages

### Already partially covered

```text
Appearance             Quick, Interface, Advanced
Wallpaper              Quick, Background
About                  About
Power                  General battery/suspend settings, Session/lock settings in Interface
Sound                  General audio protection, Services/music recognition, sidebar volume UI outside settings
Network                Services weather/networking user agent only; app launcher currently points to KDE kcm commands
Bluetooth              quick toggles and app launcher exist, settings page does not yet exist
Keyboard shortcuts     cheatsheet options exist, but no dedicated shortcut editor
Input                  limited; no dedicated input page yet
Privacy/Portals        work safety + policies exist, but no portal/privacy page yet
Displays               not covered in KOOMPI Settings yet
Workspace wallpapers   not covered yet; should be added only after workspace wallpaper behavior is stable
```

### Current gaps

```text
Displays
Network
Bluetooth
Sound
Keyboard shortcuts editor
Input
Privacy/Portals
Workspace wallpapers
Dedicated Appearance vs Advanced separation
```

## Settings source-of-truth rule

Settings should write KOOMPI config first:

```text
~/.config/koompi/config.json
```

Settings should not treat GNOME/KDE control centers as the KOOMPI source of truth.

GTK/Qt/GNOME/KDE files may still be generated/applied as compatibility outputs by KOOMPI services, but they should not own desktop behavior.

## Current compatibility/dependency concerns

Current config still contains app launcher commands that point at KDE control modules:

```text
apps.bluetooth       = kcmshell6 kcm_bluetooth
apps.manageUser      = kcmshell6 kcm_users
apps.network         = kcmshell6 kcm_networkmanagement
apps.networkEthernet = kcmshell6 kcm_networkmanagement
```

These are app launch commands, not current settings source of truth. They should be replaced later with KOOMPI-native settings pages or neutral tools, not removed abruptly.

## Small issue fixed in this milestone

`InterfaceConfig.qml` had notification monitor settings bound to:

```text
Config.options.notifications.forceMonitor
```

But the config schema and config file use:

```text
Config.options.notifications.monitor
```

This mismatch meant the UI could write to a non-schema path and the notification popup used a different key. The settings UI now uses `notifications.monitor`, matching `Config.qml`, `config.json`, and `NotificationPopup.qml`.

Changed file:

```text
~/.config/quickshell/koompi/modules/settings/InterfaceConfig.qml
```

No visual redesign was made.

## KOOMPI Settings direction

Long-term product name:

```text
KOOMPI Settings
```

User-facing documentation can call it part of:

```text
KOOMPI Desktop Experience
```

Implementation direction:

1. Keep current settings shell and component style.
2. Add pages incrementally rather than redesigning the whole settings app.
3. Prefer pages that directly control KOOMPI-owned config.
4. Use dangerous/disruptive labels for settings that restart services, change portals, affect lock/security, or modify compatibility outputs.
5. Add fallback/revert behavior for risky changes where possible.
6. Do not add KDE/GNOME control center dependencies as core settings functionality.

## Recommended page evolution

### Phase S1: Organize existing controls

No behavior changes. Improve names and grouping later:

```text
Quick -> Quick
General -> General
Bar -> Panel
Background -> Background
Interface -> Interface
Services -> Services
Advanced -> Advanced
About -> About
```

### Phase S2: Add missing KOOMPI-native pages

Add only after backing config model exists:

```text
Displays
Network
Bluetooth
Sound
Power
Keyboard
Input
Privacy/Portals
```

### Phase S3: Appearance split

When `koompi-theme` exists, split appearance into:

```text
Appearance
Wallpaper
Workspace wallpapers
Theme compatibility
```

Workspace wallpapers should remain opt-in and should not trigger global theme changes by default.

## Initial Milestone 5 decision

Milestone 5 initial pass is complete when:

- Current settings structure is documented.
- Current component style is preserved.
- Clear page gaps are listed.
- Settings source-of-truth rule is documented.
- Only safe binding fixes are applied.

No settings redesign should happen in this milestone.
