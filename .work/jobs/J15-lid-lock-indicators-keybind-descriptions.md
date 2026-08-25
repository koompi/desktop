# J15 — lid close locks; keep-awake / night-light / dictation on the bar; every keybind described

`.work/OMARCHY-AUDIT.md` O07, O11, O04. Verified 2026-08-25: `keybinds.lua:409` lid bind is commented out;
142 `hl.bind(` calls, far fewer with `description`; keep-awake has no bar presence.

## Files you own
- `dots/.config/hypr/hyprland/keybinds.lua`
- new `dots/.local/bin/koompi-lid` (lock when no external monitor; suspend handling stays with logind)
- `dots/.config/quickshell/koompi/modules/koompi/bar/BarContent.qml` and a new
  `modules/koompi/bar/ModeIndicators.qml`
- new `tests/test_keybind_descriptions.sh`
- `docs/navigation.md` (keybind table rows only); `.work/J15-report.md`

Not yours: `services/Idle.qml`, `services/Hyprsunset.qml` (read their state properties; do not change them).
`tests/test_keep_awake_lid.sh` must keep passing; read it first, it records a previous lid regression.

## Do
1. (O07) Lid switch binds (`switch:on:Lid Switch`, `locked = true`) calling `koompi-lid close|open`. Close:
   if `hyprctl monitors -j` shows only the internal panel, lock via the existing lock path (find how the
   session menu locks; reuse it) and let logind suspend as configured. Keep-awake on (`services/Idle.qml`
   inhibits the lid) must still win; prove it with the existing test.
2. (O11) A `ModeIndicators` group on the koompi bar next to the existing recording/silent indicators
   (`BarContent.qml:238,289`): keep awake, night light, Kiri dictation if its state is exposed (say so if it
   is not), each visible only when active, click toggles. Match the bar's existing sizes and Material symbols.
3. (O04) `tests/test_keybind_descriptions.sh`: every non-hidden `hl.bind(` in `keybinds.lua` and
   `custom/keybinds.lua` carries `description`. Then add the missing descriptions so it passes. Hidden binds
   stay hidden.
4. `hyprctl reload`, then run `qs -c koompi` reload and screenshot the bar with keep-awake toggled on
   (`grim -o eDP-1 .work/J15-bar.png`).

## Acceptance
1. Paste the test output before (failing, with the count) and after (passing).
2. Paste `hyprctl binds -j | jq '[.[] | select(.description=="")] | length'` after reload.
3. `.work/J15-bar.png` showing the keep-awake indicator; paste `qs log -c koompi | tail` showing no QML
   warnings from your files.
4. Paste `./tests/run.sh` tail, `tests/test_keep_awake_lid.sh` included and green.

## Out of scope
- Clamshell/external-monitor layout (omarchy's `monitor-clamshell`); only the lock decision.
- Notification keybinds (O12), cheatsheet execution (O13).

## Stop conditions
- Do not close the lid on this laptop to test; simulate with `hyprctl dispatch` of the bind's command.
- Never kill by name; never touch `~/.config/koompi/config.json`.
