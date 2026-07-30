# Navigation model

This document fixes which shell surface owns what, so a new feature has one obvious home and a shortcut has one meaning.
It describes the desktop as shipped, and marks separately what is decided but not yet built.
Where this document and the code disagree, the code is the defect.

Source of truth for the bindings themselves is `dots/.config/hypr/hyprland/keybinds.lua`, for gestures `dots/.config/hypr/hyprland/general.lua`, and for surface state `dots/.config/quickshell/koompi/GlobalStates.qml`.
The `Super+/` cheatsheet is generated from the `description` field of each bind, so a bind without a description is invisible to users.

## Roles

Six roles, and nothing else may claim a primary gesture or a bare `Super` chord.

| Role | Question it answers | Surface | Opened by | State |
| --- | --- | --- | --- | --- |
| Search | "take me to a thing" | `SearchPanel.qml` | `Super` release | `searchOpen` |
| Overview | "where are my windows" | `OverviewPanel.qml` | `Super+Tab`, 4-finger up/down | `overviewOpen` |
| Today | "what is my machine doing" | right sidebar, `SidebarRight.qml` | `Super+N` | `sidebarRightOpen` |
| Now | "what is my work doing" | left sidebar, `SidebarLeft.qml` | `Super+A` | `sidebarLeftOpen` |
| Launchpad | "show me everything installed" | `Launchpad.qml` | 4-finger spread only | `launchpadOpen` |
| Quickwork | "do this for me" | not built | `Super+O`, reserved and unbound | none yet |

Search is the primary app launcher.
Launchpad is deliberately gesture-only and takes no keyboard binding, so the two never compete for the same reflex.

Two roles are named for where they are going, not for what they are today.
**Today** is the right sidebar, which is to become header, quick controls, grouped notifications, and a secondary personal-tools tab.
**Now** is the left sidebar, which is to become Quickwork's drawer: active tasks, approvals, recent artifacts, and task continuity.
Until Quickwork exists, the left sidebar still holds the inherited AI and translator tabs, and those are the thing being replaced rather than the thing being specified.

## Entry points

A surface gets one keyboard binding, at most one pointer target, and at most one gesture.
Anything beyond that has to earn its place, because every extra way in is another thing that can disagree about the open state.

The inventory below is what exists, not what is sanctioned.
The horizontal bar and the vertical bar are alternative bars, so a given session sees one column of these, not both.

| Surface | Keyboard | Bar | Corner | Gesture | IPC |
| --- | --- | --- | --- | --- | --- |
| Left sidebar | `Super+A` | one button, hidden unless AI or translator is enabled | top-left | none | yes |
| Right sidebar | `Super+N` | one button | top-right | none | yes |
| Overview | `Super+Tab` | right-click on the workspaces widget | none | 4-finger up or down | yes |
| Search | `Super` | none | none | none | yes |
| Launchpad | none, by decision | none | none | 4-finger spread and close | yes |
| Cheatsheet | `Super+/` | none | none | none | yes |
| Window actions | none, by decision | left-click the app identity in the left section | none | none | no |
| Snap preview | none of its own, rides `Super+drag` | none | none | none | no |
| Workspace hint | none | shown under the workspaces widget on a first run | none | none | no |

Getting to one bar button per sidebar took a change on 2026-07-30.
Three bar sections were left-click toggles for a sidebar on top of the dedicated button inside that same section: the right section of the horizontal bar, and both the top and bottom sections of the vertical bar.
The consequence was that clicking the clock, the Pomodoro timer, or a gap between tray icons opened a sidebar.
The horizontal bar's left section already did it correctly, with `acceptedButtons: Qt.NoButton` and a comment saying clicks belong to the dedicated button, so the fix was to make the other three match it.
Those sections still exist for hover and for scroll-to-change-volume or brightness, which are wheel and hover behaviours and survive `NoButton`.

The window actions menu takes the one pointer path the app identity had spare, so a window's own actions are reachable without knowing a bind.
Left-clicking the icon, app name, and title opens close, float, fullscreen, pin, and move to workspace for the focused window, and clicking again closes it.
That is a click on a dedicated item, which is what the left section's `acceptedButtons: Qt.NoButton` reserves clicks for, so the section itself still opens nothing.
Right-click on the identity stays free, and the menu takes no keyboard binding and no gesture.
Each entry shows the bind that does the same thing, which is the only place the window binds appear outside `Super+/`.
It exists on the horizontal bar only, because the vertical bar shows no window identity to hang it off.
`windows.actionsMenu` turns it off, default true.

The snap preview takes no input path at all.
`Super+drag` already moves a window, and `keybinds.lua` gives that same chord a second, `transparent` bind carrying `quickshell:snapPreviewDrag`, so the shell learns when a drag starts and ends without the drag itself changing.
While one is running, pushing the pointer into a screen edge draws the rectangle the window will take, and releasing puts it there: a side gives a half, a corner a quarter, the top edge the whole usable area.
The bottom edge alone does nothing, because that is where the dock is.
The threshold is 24px, small enough that dragging a tiled window to the far edge to swap it with the window there still reads as a swap rather than a snap.
Nothing new is added to the pointer, the wheel, or any gesture, and the preview window carries an empty input mask so it cannot take a click even while it is up.
`windows.snapPreview` turns it off, default true; with it off the global shortcut is never registered and the bind above dispatches into nothing.

The first-run workspace hint deliberately does not take the workspaces widget's right-click, which belongs to Overview, or its wheel, which steps workspaces.
It is dismissed by its own button and by nothing else, so no existing click, drag, or key changes meaning while it is up.
`windows.workspaceHelp` turns it off, default true.

This matters more for the right sidebar than the count suggests.
Opening it runs `GlobalStates.onSidebarRightOpenChanged`, which times out and marks read every notification, so an accidental open destroys state.

## Edges

The left edge belongs to work continuity, the right edge to system state.
An edge never opens something from the other side.

| Edge | Opens | Live by default |
| --- | --- | --- |
| Top-left corner, 250x5 px | left sidebar | yes |
| Top-right corner, 250x5 px | right sidebar | yes |
| Bottom corners | same, mirrored | no, `sidebar.cornerOpen.bottom` defaults to false |

Corner activation as a whole is `sidebar.cornerOpen.enable`, default true, and only the corner pair matching `cornerOpen.bottom` is loaded at all.

## Gestures

| Gesture | Action |
| --- | --- |
| 3-finger swipe | move window |
| 3-finger pinch | fullscreen |
| 4-finger horizontal | switch workspace, walking numeric neighbours |
| 4-finger up or down | Overview |
| 4-finger spread | open Launchpad |
| 4-finger close | close Launchpad |

Launchpad is bound as separate open and close gestures rather than one toggle, so repeating the same motion never flaps it shut.
Hyprland's own direction names are inverted here: `pinchin` fires when the fingers move apart.

## Keyboard map

Only the primary bind is listed.
Many shell binds have a second copy guarded by `qs ipc call TEST_ALIVE ||` that runs a standalone fallback when Quickshell is not up, which is a redundancy mechanism rather than a separate binding.

### Shell surfaces

| Keys | Action |
| --- | --- |
| `Super` | Search |
| `Super+Tab` | Overview |
| `Super+A` | left sidebar |
| `Super+Alt+A` | detach left sidebar |
| `Super+N` | right sidebar |
| `Super+O` | reserved for Quickwork, unbound |
| `Super+V` | clipboard history |
| `Super+.` | emoji |
| `Super+/` | cheatsheet |
| `Super+K` | on-screen keyboard |
| `Super+M` | media controls |
| `Super+G` | widget overlay |
| `Super+J` | bar |
| `Ctrl+Alt+Delete` | session menu |
| `Ctrl+Super+T` | wallpaper selector |
| `Ctrl+Super+Alt+T` | random wallpaper |
| `Ctrl+Super+Shift+D` | light/dark mode |
| `Ctrl+Super+P` | cycle panel family |
| `Ctrl+Super+R` | restart the shell |

Clipboard and emoji belong to Search, not to Overview.
They set their own flags rather than aliasing `searchOpen`, which is what makes `Super+V` then `Super+.` switch mode instead of toggling the panel shut.

### Window

| Keys | Action |
| --- | --- |
| `Super+drag` | move, and drop into a screen edge to take that half |
| `Super+right-drag` | resize |
| `Super+arrows` | focus in direction |
| `Super+Shift+arrows` | move in direction |
| `Super+Q` | close |
| `Super+Shift+Alt+Q` | force kill |
| `Super+D` | maximize |
| `Super+F` | fullscreen |
| `Super+Alt+F` | fullscreen spoof |
| `Super+P` | pin |
| `Super+Alt+Space` | float or tile this window |
| `Super+Shift+Space` | stacking or tiling desktop |
| `Super+;` and `Super+'` | split ratio |
| `Super+Alt+1..0` | send to workspace |
| `Super+Shift+PageUp/PageDown` | send to workspace left/right |
| `Super+Alt+S` | send to scratchpad |

`Alt+F4` is caught and answered with a notification pointing at `Super+Q`, and is left non-consuming so Windows VMs still receive it.

### Workspace

| Keys | Action |
| --- | --- |
| `Super+1..0` | focus workspace |
| `Ctrl+Super+Left/Right` | focus workspace left/right |
| `Super+PageUp/PageDown` | focus workspace left/right |
| `Super+scroll` | focus workspace left/right |
| `Super+S` | scratchpad |
| `Ctrl+Super+S` | special workspace |

Number binds are duplicated on raw keycodes and on the keypad, because some layouts report number keys as other characters.

### Utilities

| Keys | Action |
| --- | --- |
| `Print` | screenshot, region or full screen |
| `Shift+Print` | whole screen to file and clipboard |
| `Super+Shift+S` | region snip |
| `Super+Shift+A` | region to image search |
| `Super+Shift+X` | region to text, OCR |
| `Super+Shift+T` | translate screen content |
| `Super+Shift+C` | pick colour |
| `Super+Shift+R` | record region |
| `Super+Shift+Alt+R` | record screen with sound |
| `Super+Space` | switch keyboard layout, EN and KM |
| `Super+-` and `Super+=` | screen zoom |

### Media

| Keys | Action |
| --- | --- |
| `Super+Shift+P` | play or pause |
| `Super+Shift+N` | next track |
| `Super+Shift+B` | previous track |
| `Super+Shift+M` | mute output |
| `Super+Alt+M` | mute microphone |

The `XF86Audio*` and `XF86MonBrightness*` keys carry the same actions and are marked `locked` so they work on the lock screen.

### Session

| Keys | Action |
| --- | --- |
| `Super+L` | lock |
| `Super+Shift+L` | sleep |
| `Ctrl+Shift+Alt+Super+Delete` | shut down |

### Apps

| Keys | Action |
| --- | --- |
| `Super+Return`, `Super+T` | terminal |
| `Super+E` | file manager |
| `Super+W` | browser |
| `Super+C` | code editor |
| `Super+X` | text editor |
| `Super+I` | settings |
| `Ctrl+Shift+Escape` | task manager |
| `Super+`` ` `` | terminal panel |
| `Super+\` | system monitor panel |
| `Super+Y` | Telegram panel |

App binds are the one group that may grow, because they name what the user installed rather than what the shell owns.
Anything opened as a scratchpad panel rather than a normal window is a shell surface and belongs to a role above.

### Kiri

Kiri's voice binds live in `dots/.config/hypr/custom/keybinds.lua`, which is user-owned and never overwritten by an update.

| Keys | Action |
| --- | --- |
| AI key, `Super+Shift+code:201` | English dictation |
| AI key with Alt | Khmer dictation |
| `Super+Shift+K` | Khmer dictation |
| `Super+Escape` | cancel dictation |
| `Super+Alt+K` | Kiri settings |

## Super on its own

Search opens when `Super` is *released*, which makes every other `Super` chord ambiguous until the release arrives.
The resolution is that pressing anything else while `Super` is held cancels the pending toggle.
Hyprland spells this `binditn = SUPER, catchall`, which `hl.bind` rejects, so `keybinds.lua` wraps `hl.bind` and gives every `Super` chord a companion bind carrying `quickshell:searchToggleReleaseInterrupt`.

Two rules follow, and both have been got wrong before.

The wrapper must stay installed for the rest of the config, including `custom/keybinds.lua`, or a user's own `Super` chord opens Search on release.

The only chord exempt is `Super`'s own keysym, `SUPER_L` and `SUPER_R`, because that press is what arms the toggle.
Mouse buttons are not exempt.
`Super+drag` is a chord like any other, and exempting it left the toggle armed for the whole drag, so letting go of `Super` opened Search over the window just moved.

## Panel contract

One surface, one owner of its open state, one focus grab, and keyboard focus only while open.

The shared mechanism is the `GlobalFocusGrab` singleton in `services/`.
A surface calls `addDismissable` when it becomes visible and `removeDismissable` when it stops, and closes itself on the singleton's `dismissed` signal.
A surface that should be inside the grab but must not be closed by a click outside, such as the bar and the on-screen keyboard, registers with `addPersistent` instead.
`SearchPanel.qml` and `OverviewPanel.qml` are the reference implementations.

Conformance as of 2026-07-30:

| Surface | Grab | Keyboard focus |
| --- | --- | --- |
| Search | dismissable | gated on `searchOpen` |
| Overview | dismissable | gated on `overviewOpen` |
| Right sidebar | dismissable | gated on `sidebarRightOpen` |
| Left sidebar | dismissable | unconditional `OnDemand`, harmless because the window is gated on `sidebarLeftOpen` |
| Wallpaper selector | dismissable | unconditional `OnDemand`, window gated by its loader |
| Media controls | dismissable | not set |
| Cheatsheet | dismissable | gated on `cheatsheetOpen` |
| On-screen keyboard | persistent, correctly | commented out |
| Global menu | own `HyprlandFocusGrab` over the bar and every open popup | bar takes focus only while a menu is open |
| Window actions menu | own `HyprlandFocusGrab` over the bar and every open popup | bar takes focus only while a menu is open |
| Snap preview | none needed, empty input mask | `None` |
| Workspace hint | none, dismissed by its own button only | `None` |
| Launchpad | none needed, see below | gated on `launchpadOpen`, `Exclusive` |
| Widget overlay | own grab, left `active: false` | conditional, pinned widgets stay up by design |
| Region selector | none, modal capture surface | unconditional `OnDemand` |
| Screen translator | none, modal capture surface | unconditional `OnDemand` |
| Session menu | none, modal | `Exclusive`, loader-gated |

An unconditional `OnDemand` is not by itself a bug: a layer surface whose `visible` is gated on its own flag has no surface to focus while closed.
`OnDemand` is also the correct value rather than `Exclusive`, because since Hyprland 0.49 `Exclusive` breaks click-outside-to-close.

`GlobalFocusGrab` is only meaningful for a surface a click can land beside.
Launchpad and the modal capture surfaces cover the whole screen and dismiss themselves from their own input, so their absence from the grab is correct rather than missing.
Launchpad closes on a click anywhere on its background and on `Escape`, and the region selector and screen translator close on `Escape`.
The snap preview and the first-run workspace hint are absent for the same reason read the other way: the preview accepts no input at all, and the hint is masked to its own rectangle, so a click beside either lands on whatever is underneath and neither has anything to dismiss.

A surface that is fullscreen but masked to a smaller item, like the cheatsheet, is the case that does need the grab: outside the mask the click reaches the window beneath, and the grab is the only thing that notices.

The remaining gap is the one surface whose keyboard focus is set but not gated.
The wallpaper selector and the left sidebar both ask for `OnDemand` unconditionally, which is currently harmless and will stop being harmless the moment either window outlives a single open.

## Rules for adding to this model

A new capability joins an existing role.
If it does not fit one, the model is wrong and this document changes first.

A new bind carries a `description` prefixed with its group, or it will not appear in the cheatsheet.

A new panel registers with `GlobalFocusGrab` and gates `WlrLayershell.keyboardFocus` on its own open flag, both, not one.

A surface gets exactly one keyboard entry point.
Extra ways in belong to pointer and gesture, and each of those needs a reason to exist beyond being possible.
