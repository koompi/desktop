# J32 — OSD from the command line, a battery-low hook, and one TUI launch convention (O23 O29, ALREADY BUILT battery row)

Serial after J31 (it adds `koompi-toggle` to `koompi-shell/PKGBUILD` `_tools`; you add `koompi-osd` beside it and bump
pkgrel once more). `.work/OMARCHY-AUDIT.md` rows O23, O29, and the ALREADY BUILT line "fire `koompi-hook battery-low`".
Omarchy at `~/.tmp/omarchy`: `bin/omarchy-osd:27-40`, `bin/omarchy-launch-tui:6-13`, `bin/omarchy-tui-install:76-92`,
`default/hypr/apps/terminals.lua:5-8`, `bin/omarchy-battery-low:11-12`. Shell root `Q=dots/.config/quickshell/koompi`.
Read first: `$Q/modules/koompi/onScreenDisplay/OnScreenDisplay.qml` (237; `indicators` table at line 19, `IpcHandler
osdVolume` at 206), `$Q/modules/koompi/onScreenDisplay/OsdValueIndicator.qml`, `$Q/services/Battery.qml:49-70`,
`dots/.local/bin/koompi-hook` (events list at the `case` near line 19), `dots/.config/hypr/hyprland/scripts/launch_sysmon.sh`,
`launch_first_available.sh`, `toggle_app_scratchpad.sh`, `rules.lua` (231; the scratch rules), `keybinds.lua:60-61`,
`sdata/dist-arch/koompi-shell/PKGBUILD`, `tests/test_packaged_tools.sh`, `tests/test_hook*.sh`.

## Files you own
- `$Q/modules/koompi/onScreenDisplay/OnScreenDisplay.qml` (QML cap 400) and `indicators/**`
- `$Q/services/Battery.qml`
- `dots/.local/bin/koompi-hook` (the event list only), new `dots/.local/bin/koompi-osd`, new `dots/.local/bin/koompi-launch-tui`
- `sdata/dist-arch/koompi-shell/PKGBUILD` (`_tools` rows, pkgrel +1), `cli/src/main.zig` (one `osd` row + test)
- `dots/.config/hypr/hyprland/scripts/launch_sysmon.sh`, `dots/.config/hypr/hyprland/rules.lua`
- `docs/agents/hooks.md` (the events table row), new `tests/test_osd_cli.sh`; `.work/J32-report.md`

## Do
1. (O23) A generic OSD message: `IpcHandler` target `osd` with `show(icon, message, progress, duration)`, where `progress`
   is -1 for "no bar"; it reuses the existing OSD window and timeout (`triggerOsd`) and renders through a new
   `indicators/OsdMessage.qml` next to the value indicators — no second window. `koompi-osd -i <material-icon> -m <text>
   [-p 0..100] [-d ms]` calls it; usage on bad args, exit 2 when the shell is not running. Register `osd` in `cli/src/main.zig`.
2. (battery) `Battery.qml` fires `koompi-hook battery-low` (via `Quickshell.execDetached`, once per crossing, the way the
   notification fires) and `battery-critical` likewise; both events added to `koompi-hook`'s allowed list and to the table in
   `docs/agents/hooks.md`. Keep the notification and the sound.
3. (O29) `koompi-launch-tui <app-id> <command...>`: runs the terminal the tree prefers (`variables.lua` names it) with
   `--class TUI.<app-id>`, through `koompi-launch` (J21's app.slice scope) — cite the file. `rules.lua`: one rule for
   `^TUI\.` classes (float, centre, a size like the portal rule at `rules.lua:36-38`) with a comment; `launch_sysmon.sh`
   becomes a `koompi-launch-tui sysmon-scratch ...` call and its scratch rule keeps matching (prove with `hyprctl clients`
   after opening it — opening the sysmon widget is allowed).
4. `tests/test_osd_cli.sh`: shim `qs` and prove the argument table and exit codes for both new tools; qmllint the OSD files;
   `luac -p rules.lua`; `test_packaged_tools.sh` and the hook test still pass.

## Acceptance
1. Paste the new test's output, `tests/test_packaged_tools.sh`, and the `./tests/run.sh` tail (post-J31 baseline, +1).
2. Live: `koompi-osd -i check -m "hello" -p 40` on this machine and a screenshot of the OSD (`grim` to `/tmp/j32-osd.png`).
3. Live: `Super+\` (or the script) opens the sysmon widget; paste the `hyprctl clients -j | jq '.[] | select(.class|startswith("TUI."))'` row.
4. `cd cli && zig build test`; `wc -l` of every touched file under cap.

## Out of scope
- The volume/brightness OSD behaviour, `koompi-launch` itself, `keybinds*.lua` (report a needed bind), Search rows.

## Stop conditions
- Never restart the live shell; the new IpcHandler is proven only after Rithy's shell reloads, so prove it with
  `qs -c koompi ipc show` on a second instance ONLY if that is safe (it is not: two instances fight for layer surfaces) —
  instead paste the qmllint result and the shim test, and say the live call is unverified until the next `koompi reload`.
- If `koompi-hook`'s event list is validated by a test fixture you do not own, stop and report the file.
