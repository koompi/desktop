# J34 report — update badge on the KOOMPI bar, bar popups by keyboard (O09 O34)

Branch `j34-update-badge-bar-keys`, four commits on top of `a76a797b` (J31 report). Nothing pushed, main untouched.

## What landed

**O09, `29456614`.** `modules/koompi/bar/UpdateBadge.qml` (new, 80 lines): a `Revealer` in the indicator cluster right after
`ModeIndicators`, lit while `Updates.available && Updates.count > 0`, `system_update` icon plus the count, tooltip
"N updates — click to run `koompi update`, middle-click to check again". Click: `Hyprland.dispatch("exec [float;center;size 70% 70%]
bash -c '...'")` where the script walks variables.lua's terminal order (`wezterm foot "kitty -1" alacritty konsole kgx uxterm
xterm`), takes the first installed (or `$TERMINAL`), and runs `koompi-launch --id koompi-update --terminal "$t" -- bash -c "koompi
update; read -rsn1 -p ..."` so the transcript stays until a key. `koompi-launch-tui` is **not** on main (J32 unmerged), so
`--terminal` is koompi-launch's own contract. Middle-click: `Updates.refresh()`. `BarContent.qml` 377 → 382 lines, badge referenced
once. `services/Updates.qml`: skips the check while `Battery.isLow && !Battery.isCharging`; `KOOMPI_UPDATES_FORCE=N` fakes a count
(header comment documents it; only the test sets it). Six hours: `Config.options.updates.checkInterval` is a user-facing settings
knob (`ServicesConfig.qml:221`), so the interval stays on the knob and its **default** moves 120 → 360 in `Config.qml:772` — a
one-line touch outside my files, flagged below. Why 6 h: mirrors refresh their package databases a few times a day, so a shorter
interval re-syncs the same index for the same answer (omarchy uses the same 21600000 ms). "Refresh on graphical-session start" is
the existing settle timer: the first check fires ten minutes after the shell starts (commit `8cbbbb84` moved it off the first
frame on purpose); I kept that and reworded the comment.

**O34, `1196567c`.** `Bar.qml` IpcHandler `bar`: `popup(n)` opens the n-th right-section popup on the focused monitor (fallback:
first bar), toggling if it is already open; `popupClose()` clears every bar. State is one `keyboardPopup` int on each bar
`PanelWindow`, so opening one closes the others and no singleton changes. `StyledPopup.qml`: `keyIndex`, `keyboardOpen` (index
matches and the host widget is visible), `active` ORs it in, `WlrLayershell.keyboardFocus` OnDemand only while keyboard-opened,
joins `GlobalFocusGrab` as dismissable (late-join if a hover popup is then keyboard-opened), `Keys.onEscapePressed: close()`.
Order (Bar.qml comment, `docs/navigation.md:53`, lua descriptions): **1 agent usage, 2 battery, 3 pomodoro, 4 clock**; 5–9 bound and
idle. Not counted: media (Super+M toggles its own controls), the indicator cluster (Super+N, sidebar), the tray.
`keybinds_notifications.lua` → `keybinds_shell_extra.lua` (git rename, notification chords unchanged at the top), nine
`SUPER + CTRL + n` binds via `hl.dsp.exec_cmd("qs -c $qsConfig ipc --any-display call bar popup n")` each described
`Shell: bar popup n (...)`, plus hidden `code:10..18` twins the way keybinds.lua does for number keys. `hyprland.lua` require updated;
`keybinds.lua` untouched at 447. Stale references fixed: `Notifications.qml:266` comment, `tests/test_toggle_cli.sh` (path, count now
matches the four notification binds, require check).

**Tests, `5ca6ec71`.** `tests/test_bar_keys.sh`, described under Acceptance 1.

## Files touched outside the ownership list
- `modules/common/Config.qml:772` — one line, `checkInterval` default 120 → 360 (reason above).
- `services/Notifications.qml:266` — comment names the renamed lua file.
- `tests/test_toggle_cli.sh` — J31's test pinned the old filename; three lines.

## Acceptance 1: tests

`tests/test_bar_keys.sh` (standalone, `BAR_SHOT=/tmp/j34-bar.png`):
```
ok   luac: keybinds_shell_extra.lua and hyprland.lua parse
ok   chords: 9 described Super+Ctrl+N binds, Bar.qml implements popup(n) and popupClose()
ok   popups: keyIndex 1 agent usage, 2 battery, 3 pomodoro, 4 clock; Escape closes
ok   BarContent.qml: 382 lines, badge referenced once
ok   qmllint: 9 bar files parse without errors
skip: keybinds_shell_extra.lua is not installed in the live config, hyprctl binds not checked
PASS popup 4 keyboardOpen after ipc, window mapped
PASS saved bar.png 1280x63
PASS saved popup.png 226x110
PASS popup 4 closed by the second call
PROBE DONE
     bar image at /tmp/j34-bar.png, popup at /tmp/j34-bar-popup.png
ok   headless: bar rendered with 12 forced updates, bar popup 4 opened and closed over IPC
```
The chord count runs the lua under a stub `hl` (so the loop is executed, not grepped) and asserts chord n is `SUPER + CTRL + n`.
The probe also fails on any QML `Binding loop` in the nested shell's log (the first badge draft had one, through the Revealer's
childrenRect; fixed by not anchoring inside it).

`tests/test_keybind_descriptions.sh`:
```
keybind descriptions: all 149 binds described or hidden
```

`./tests/run.sh` tail (post-J31 baseline +1; the new test lands in the skipped column here because the live config does not
carry the lua file yet — its `skip:` line is the hyprctl one, the headless part passed):
```
83 passed, 4 skipped, 0 failed
skipped: test_bar_keys.sh test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

## Acceptance 2: live

**Blocked.** Copying `keybinds_shell_extra.lua` into `~/.config/hypr/hyprland/` and editing the live `hyprland.lua` was denied by
the permission classifier twice (first with `rm` of the old file, then a bare `cp` + backup). I did not work around it. The live
`~/.config/hypr/hyprland.lua` equals the repo's pre-J34 one (diffed), and the live `keybinds_notifications.lua` equals HEAD's. To
install and verify (the IPC target does not exist in the running shell yet, so the chords are inert until the shell reloads):
```
cp ~/.config/hypr/hyprland/keybinds_notifications.lua ~/.config/hypr/backups/keybinds_notifications.lua.j34
cp ~/workspace/koompi-desktop/dots/.config/hypr/hyprland/keybinds_shell_extra.lua ~/.config/hypr/hyprland/
sed -i 's|require("hyprland.keybinds_notifications")|require("hyprland.keybinds_shell_extra")|' ~/.config/hypr/hyprland.lua
rm ~/.config/hypr/hyprland/keybinds_notifications.lua
hyprctl reload && hyprctl binds | grep -c 'bar popup'      # expect 9
```
(after `git merge` of this branch; the lua file is self-contained so it also works from the worktree path.)

The badge and the IPC handler cannot be seen in the live shell until Rithy reloads it; the nested-instance run above is the
substitute. qmllint over the nine QML files I touched, Qt 6 `/usr/lib/qt6/bin/qmllint -I <root-as-qs> -I /usr/lib/qt6/qml`:
```
Bar.qml                rc=0 errors=0 warnings=86  (import/unqualified: 78)
BarContent.qml         rc=0 errors=0 warnings=147 (import/unqualified: 136)
UpdateBadge.qml        rc=0 errors=0 warnings=28  (import/unqualified: 27)
StyledPopup.qml        rc=0 errors=0 warnings=65  (import/unqualified: 63)
AgentUsagePopup.qml    rc=0 errors=0 warnings=10  (import/unqualified: 10)
BatteryPopup.qml       rc=0 errors=0 warnings=32  (import/unqualified: 32)
PomodoroPopup.qml      rc=0 errors=0 warnings=28  (import/unqualified: 27)
ClockWidgetPopup.qml   rc=0 errors=0 warnings=16  (import/unqualified: 16)
Updates.qml            rc=0 errors=0 warnings=21  (import/unqualified: 16)
```
The non-import warnings are the pre-existing classes (`QProcess::ExitStatus` on `onExited`, singleton members "not found" because
the `qs` module does not resolve under qmllint — `PowerSaving.interval` had the same one before this job).

## Acceptance 3: headless capture

`/tmp/j34-bar.png` (1280×63): the bar with `KOOMPI_UPDATES_FORCE=12` — indicator cluster shows network, the badge `⭳ 12`, mic-off,
17:37. `/tmp/j34-bar-popup.png` (226×110): the clock popup (date, uptime, to-do) opened by `qs ipc call bar popup 4`.

How: J04's cage route does not work for the bar — cage has no layer-shell (`Failed to initialize layershell integration`, blank
frame), and Hyprland nested under cage aborts (`xdg_wm_base` v6 vs v5). `kwin_wayland --virtual --no-lockscreen
--no-global-shortcuts --exit-with-session inner.sh` hosts layer-shell; `grim` cannot capture there (KWin exposes no screencopy to it),
so the probe grabs the QML items with `grabToImage` (a window's `contentItem` is Quickshell's proxy and refuses; the bar's first
child and the popup's background are what get grabbed). The nested `qs` runs with `HYPRLAND_INSTANCE_SIGNATURE` unset, XDG dirs in
a temp dir, a `koompi-shelld` shim, so it never talks to the live Hyprland or config. ~25 s per run.

## Unverified until the shell reloads
- Escape: the popup asks for the keyboard `OnDemand` when keyboard-opened. Hyprland focuses an on-demand layer surface on map;
  the hover-then-keyboard case relies on the interactivity change on commit doing the same. KWin virtual has no input device, so
  the key itself was not pressed headlessly.
- The click path (`Hyprland.dispatch` exec rules → koompi-launch → terminal `-e`) — same contract koompi-launch already uses for
  `Terminal=true` entries; `wezterm --help` lists `-e` as the `start` alias.

## Notes for the lead
- Stop conditions honoured: no shell restart or kill, no sudo, no session lock, no keep-awake toggle, `~/.config/koompi/config.json`
  untouched; the only live write attempted was the lua install, and it was denied, so the live config is exactly as J31 left it.
- The test's run.sh status will read "skipped" on any machine without the lua file installed live; that is the designed `skip:`.
- A `checkInterval` already persisted in a user's `config.json` stays at its value; only the default moved.
- If J32 lands `koompi-launch-tui`, `UpdateBadge.runUpdate` is the one string to swap.
