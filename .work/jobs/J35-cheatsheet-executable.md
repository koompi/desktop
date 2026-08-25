# J35 — Cheatsheet rows searchable and executable (O13)

`.work/OMARCHY-AUDIT.md` row O13. Omarchy at `~/.tmp/omarchy`: `bin/omarchy-menu-keybindings:630-669` (`dispatch_binding`: `exec` →
run the command, `sendshortcut` → key down/up, default → `hyprctl dispatch <dispatcher> <arg>`). Shell root `Q=dots/.config/quickshell/koompi`.
Read first: `$Q/services/HyprlandKeybinds.qml` (118: the parsed record at :38-48 already carries `dispatcher` and `arg`),
`$Q/modules/koompi/cheatsheet/CheatsheetKeybindsCategory.qml` (225: `component BindLine` at :171-224, no MouseArea),
`$Q/modules/koompi/cheatsheet/Cheatsheet.qml` (242: open/close at :29-37, `WlrKeyboardFocus.OnDemand` at :60, IpcHandler :200-234),
`$Q/modules/koompi/cheatsheet/CheatsheetKeybinds.qml` (59), `$Q/services/LauncherSearch.qml` for how Search already runs a
`hyprctl dispatch` (grep `dispatch`), `tests/test_qml_layering.sh`, `tests/test_services_qml_bugs.sh` (qmllint pattern).

## Files you own
- `$Q/modules/koompi/cheatsheet/**` (every file ≤ 400; new files welcome)
- `$Q/services/HyprlandKeybinds.qml`
- new `tests/test_cheatsheet_dispatch.sh`; `.work/J35-report.md`

## Do
1. `HyprlandKeybinds.dispatch(bind)`: `exec` → `Quickshell.execDetached(["hyprctl","dispatch","exec", arg])` (through
   `koompi-launch` if the arg is a bare app launch — say how you decide, or always via hyprctl and say why); everything
   else → `hyprctl dispatch <dispatcher> <arg>`; `global` dispatchers (`quickshell:*`) are called directly through
   `hyprctl dispatch global`. Binds with `catchall`/submap rows are not dispatchable: `dispatchable(bind)` says so.
2. `BindLine` becomes clickable: hover highlight, click → `dispatch` then close the cheatsheet (the bind's own surface
   opening after the cheatsheet closes is the point). Non-dispatchable rows are not highlighted.
3. A search field at the top of the cheatsheet (focused on open, `Escape` clears then closes): filters rows by key text,
   description, and category with the tree's fuzzy helper (`modules/common/functions/fuzzysort.js`, the way Search uses it);
   `Enter` dispatches the first match. Keyboard focus is `OnDemand` today — verify typing reaches the field on open.
4. `tests/test_cheatsheet_dispatch.sh`: qmllint on every cheatsheet file + `HyprlandKeybinds.qml`; a `qs -p` probe (like
   `tests/test_ai_threads.sh` does, skipping with a `skip:` line without `qs`) that loads `HyprlandKeybinds` with a fixture
   `hyprctl` shim printing three binds (exec, workspace, global) and asserts `dispatchable` and the argv `dispatch` builds
   (shim `hyprctl` to echo its argv into a file).

## Acceptance
1. Paste the new test's output and the `./tests/run.sh` tail (baseline +1).
2. Live (allowed: opening the cheatsheet is harmless): `Super+/`, type "screenshot", Enter — paste `hyprctl dispatch` shim
   output or a screenshot at `/tmp/j35-cheatsheet.png` showing the filtered rows. If the live shell has not reloaded your
   QML, say so and paste the probe instead.
3. `wc -l` of every touched file under 400.

## Out of scope
- `keybinds.lua` and Lua files, `Config.qml` (add no option; if one is unavoidable, stop and report), Search, `docs/navigation.md` beyond one row.

## Stop conditions
- Never restart the live shell. Never run a bind whose dispatcher is `exit`, `killactive`, `dpms`, or `exec` of anything
  that changes state on this machine while testing; the shim covers dispatch.
