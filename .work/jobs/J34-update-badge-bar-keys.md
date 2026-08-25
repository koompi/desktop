# J34 — Update badge on the KOOMPI bar, and bar popups reachable by keyboard (O09 O34)

Serial after J31 (it owns `keybinds.lua`, `keybinds_notifications.lua` and `hyprland.lua` until it merges; after that they are
yours). `.work/OMARCHY-AUDIT.md` rows O09 and O34. Omarchy at `~/.tmp/omarchy`: `shell/plugins/bar/widgets/SystemUpdate.qml:11-21`,
`manual/30-updates.md:7`, `default/hypr/bindings/utilities.lua:109-115`. Shell root `Q=dots/.config/quickshell/koompi`.
Read first: `$Q/services/Updates.qml` (79: `available`, `count`, `updateAdvised`, `refresh()`), `$Q/modules/waffle/bar/UpdatesButton.qml`
(the only consumer today), `$Q/modules/koompi/bar/BarContent.qml` (377 of a 400 cap: at most a one-line `Loader`; the widget
is its own file), `$Q/modules/koompi/bar/ModeIndicators.qml` (J15's indicator pattern), `$Q/modules/koompi/bar/Bar.qml:232`
(IpcHandler `bar`), `$Q/modules/koompi/bar/*Popup.qml` (the popups: Battery, Clock, Resources, Pomodoro, AgentUsage, GlobalMenu),
`docs/navigation.md:40-54`, `tests/test_keybind_descriptions.sh`, `tests/test_services_qml_bugs.sh` (qmllint pattern).

## Files you own
- new `$Q/modules/koompi/bar/UpdateBadge.qml`, `$Q/modules/koompi/bar/BarContent.qml` (≤ 400 lines), `$Q/modules/koompi/bar/Bar.qml`,
  the `*Popup.qml` files under `$Q/modules/koompi/bar/` (open/close by index only)
- `$Q/services/Updates.qml`
- `dots/.config/hypr/hyprland/keybinds_notifications.lua` → rename to `keybinds_shell_extra.lua` if you add the popup chords there
  (update the `require` in `hyprland.lua`); `keybinds.lua` stays ≤ 447
- `docs/navigation.md` (the table rows), new `tests/test_bar_keys.sh`; `.work/J34-report.md`

## Do
1. (O09) `UpdateBadge.qml`: visible only when `Updates.available`, shows the count, tooltip "N updates — click to run
   `koompi update`", click opens a floating terminal running `koompi update` through `koompi-launch` (use the terminal
   `variables.lua` names; if J32 has merged `koompi-launch-tui`, use it and say so). Middle-click → `Updates.refresh()`.
   Place it in the right section beside `ModeIndicators`. `Updates.qml`: refresh on `graphical-session` start and every
   6 h (a Timer; say why 6 h), never while on battery below the low threshold (`Battery.isLow`), and only when `checkupdates`
   exists (it already probes `which`).
2. (O34) `Bar.qml` IpcHandler `bar`: `popup(n)` opens the n-th right-section popup (1-based, left to right as rendered;
   list the order in a comment and in `docs/navigation.md`), toggling if it is already open, closing the others; `popupClose()`.
   Binds `Super+Ctrl+1..9` → `qs ipc call bar popup N` via `hl.dsp.global` or `exec_cmd` (match what the file does for other
   IPC binds), each with a `description`. Escape closes an open popup (check whether popups already handle it).
3. `tests/test_bar_keys.sh`: `luac -p` on the lua files; qmllint on the bar files you touched; `hyprctl binds` (when a
   session exists) lists the nine chords with descriptions, else `skip:` line the way other tests do; grep proves
   `BarContent.qml` ≤ 400 and the badge is referenced exactly once.

## Acceptance
1. Paste the new test's output, `tests/test_keybind_descriptions.sh`, and the `./tests/run.sh` tail (post-J31 baseline, +1).
2. Live after `hyprctl reload` (allowed): `hyprctl binds | grep -c 'bar popup'` = 9. The IPC handler and the badge are
   unverifiable live until Rithy reloads the shell — say so; paste qmllint instead.
3. A headless capture of the bar with `Updates.available = true` forced (the way J04 captured its sections: cage + qs on a
   nested instance, `KOOMPI_UPDATES_FORCE=N` env or a `Config` flag you add and document) at `/tmp/j34-bar.png`.

## Out of scope
- `libexec/update` (J30), the waffle bar, the vertical bar, Search rows, `koompi-launch-tui` itself.

## Stop conditions
- Never restart the live shell. If `BarContent.qml` cannot take the badge in the lines it has left, move the right-section
  `Row` into its own file first as a separate commit and say so.
- If a popup has no programmatic open today (hover-only), report which and open the ones that do; do not rewrite popups.
