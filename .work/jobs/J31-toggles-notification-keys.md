# J31 — `koompi toggle <thing>` with a predicate, and notification keybinds (O24 O12)

`.work/OMARCHY-AUDIT.md` rows O24 and O12. Omarchy at `~/.tmp/omarchy`: `bin/omarchy-toggle:11-17`,
`bin/omarchy-toggle-enabled:6`, `manual/13-toggles-idle-screensaver.md:8-22`, `default/hypr/bindings/utilities.lua:24-28`.
Shell root `Q=dots/.config/quickshell/koompi`. Read first: `$Q/services/Idle.qml` (keep awake, 80 lines),
`$Q/services/Hyprsunset.qml` (night light, 171), `$Q/services/Notifications.qml` (silent + list, 310), one existing
`IpcHandler` (e.g. `$Q/modules/koompi/onScreenDisplay/OnScreenDisplay.qml:206`), `dots/.config/hypr/hyprland/keybinds.lua`
(447 lines, at its allow-list row: it may not grow), `dots/.config/hypr/hyprland.lua` (the loader), `cli/src/main.zig`
(command table at line 13-36), `sdata/dist-arch/koompi-shell/PKGBUILD` `_tools`, `tests/test_packaged_tools.sh`,
`tests/test_keybind_descriptions.sh`.

## Files you own
- `$Q/services/Idle.qml`, `$Q/services/Hyprsunset.qml`, `$Q/services/Notifications.qml`
- new `dots/.local/bin/koompi-toggle`
- `cli/src/main.zig` (one command row + its test), `sdata/dist-arch/koompi-shell/PKGBUILD` (`_tools` row, pkgrel 4 → 5)
- `dots/.config/hypr/hyprland/keybinds.lua`, `dots/.config/hypr/hyprland.lua`, and a new
  `dots/.config/hypr/hyprland/keybinds_notifications.lua` if you need the room
- `docs/navigation.md` (the keybind rows only)
- new `tests/test_toggle_cli.sh`; `.work/J31-report.md`

## Do
1. (O24) One `IpcHandler` per service: targets `idle` (`inhibit` on/off/toggle/status), `nightlight` (on/off/toggle/status),
   `notifications` (`silent` on/off/toggle/status). `status` returns the literal `on`/`off` so a script can test it. Reuse
   the state each service already holds (`Idle.toggleInhibit`, Hyprsunset's manual override — find it, `Notifications.silent`);
   do not add a second copy of the state.
2. (O24) `dots/.local/bin/koompi-toggle <keep-awake|night-light|silent> [on|off|status]`: `qs -c koompi ipc call ...`;
   with no verb it toggles and prints the new state; `status` exits 0 for on, 1 for off, 2 when the shell is not running
   (so `koompi-toggle silent status && ...` works in hooks and in J34's Search rows). Register `toggle` in
   `cli/src/main.zig` beside `hook` (`koompi toggle silent`), add the `findCommand` test case, add the tool to `_tools`.
3. (O12) Notification keybinds, all in the shell via IPC on the `notifications` target: dismiss the newest toast, dismiss
   all, invoke the newest toast's default action (`attemptInvokeAction` exists at `Notifications.qml:244`), open the
   history (the right sidebar's notification page — find the global it already exposes). Bind them; cite omarchy's four
   chords and say which you changed and why (collisions with `keybinds.lua`: check `Super+,`/`Super+Shift+,` etc. with
   `grep -n`). Every bind has a `description` (`tests/test_keybind_descriptions.sh` enforces it).
4. `keybinds.lua` may not exceed 447 lines: put the new binds in `keybinds_notifications.lua`, required from
   `hyprland.lua` right after `require("hyprland.keybinds")`, with a comment saying why it is a separate file.
5. `tests/test_toggle_cli.sh`: shims `qs` on PATH and proves the argument table (three things × four verbs, exit codes 0/1/2,
   unknown thing → usage + exit 64); `luac -p` on both lua files; qmllint on the three services (the way
   `tests/test_services_qml_bugs.sh` runs it).

## Acceptance
1. Paste the new test's output, `tests/test_packaged_tools.sh`, `tests/test_keybind_descriptions.sh`, and the
   `./tests/run.sh` tail (baseline 81/3/0, +1).
2. Live, on this machine (your shell instance, not a restart): `koompi-toggle night-light status; echo $?` twice around a
   `koompi-toggle night-light` and back — paste it. Do the same for `silent`. Do NOT toggle `keep-awake` live (Rithy's
   session runs with it on): prove it through the shim only.
3. `cd cli && zig build test`: paste. `wc -l keybinds.lua` ≤ 447.
4. `hyprctl binds | grep -c` your four new binds after `hyprctl reload` — reload is allowed; it does not restart the shell.

## Out of scope
- Bar indicators for these states (O11 landed in J15), Search rows (J34), the cheatsheet.
- Any other service, `Persistent.qml`, `Config.qml`.

## Stop conditions
- Never restart or kill the live shell (`qs`), never touch keep-awake live, never `killall`.
- If Hyprsunset has no manual override today (only the schedule), stop and report how it is modelled before adding one.
