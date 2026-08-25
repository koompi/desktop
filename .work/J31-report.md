# J31 report — `koompi toggle <thing>` with a predicate, and notification keybinds (O24, O12)

Branch `j31-toggles-notif-keys`. Files touched: `services/{Idle,Hyprsunset,Notifications}.qml`, new `dots/.local/bin/koompi-toggle`,
`cli/src/main.zig`, `sdata/dist-arch/koompi-shell/PKGBUILD` (pkgrel 4 → 5, `_tools` + koompi-toggle), new
`dots/.config/hypr/hyprland/keybinds_notifications.lua`, `dots/.config/hypr/hyprland.lua`, `docs/navigation.md` (four rows),
new `tests/test_toggle_cli.sh`. `keybinds.lua` untouched (447 lines).

## What was built

### O24: one IPC handler per service, one tool in front of them
- `Idle.qml`: target `idle`, `inhibit(verb)` → `toggleInhibit(true|false|null)`; state is `Idle.inhibit` (Persistent-backed), nothing new.
- `Hyprsunset.qml`: target `nightlight`, `on()/off()/toggle()/status()` → `toggleTemperature(true|false|undefined)`, the same
  manual override the sidebar switch uses (`manualActive`, set at the first manual flip and cleared at the next schedule edge in
  `reEvaluate`). `status` reads `temperatureActive`, which is what the screen is doing whether the schedule or the override put it there.
  Stop condition "no manual override" did not apply: the override exists at `Hyprsunset.qml:37-39,153-166`.
- `Notifications.qml`: target `notifications`, `silent(verb)` on `Notifications.silent`.
- Every verb returns the literal `on`/`off`; an unknown verb returns a `usage:` line, which the tool treats as no answer.
- `koompi-toggle <keep-awake|night-light|silent> [on|off|toggle|status]`: `qs -c koompi ipc --any-display call …`. Bare = toggle.
  Prints the resulting state on every verb; exit 0 on, 1 off, 2 shell not running (qs exit 255) or shell too old to have the target
  (`Target not found.` on stdout with exit 0; detected because the answer is not on/off), 64 usage. So `koompi-toggle silent status && …`
  works in a hook and in J34's rows.
- `koompi toggle` registered beside `hook` (helper `koompi-toggle`); help text, `command_names` and the three completion strings carry it;
  `findCommand("toggle").?.helper` asserted in the alias test.

### O12: notification chords, in `keybinds_notifications.lua`
Omarchy's chords (`default/hypr/bindings/utilities.lua:24-28`), taken unchanged: `grep -in comma` over `keybinds.lua` and
`custom/keybinds.lua` finds no bind (only the word "Command"), so nothing collided and nothing was moved.

| Chord | Omarchy | Here (IPC on `notifications`) | Returns |
| --- | --- | --- | --- |
| `Super+,` | dismissOne | `dismissOne` — newest popup → `timeoutNotification` | `ok` / `none` |
| `Super+Shift+,` | dismissAll | `dismissAll` → `timeoutAll` | `ok` / `none` |
| `Super+Alt+,` | invokeLast | `invokeLast` — the `default` action if the sender registered one, else its first; `attemptInvokeAction` (discards after) | `ok` / `none` |
| `Super+Shift+Alt+,` | showHistory | `showHistory` → `GlobalStates.sidebarRightOpen = true` (the right sidebar's notification list is its main page; `sidebarRightOpen` is the global the sidebar already exposes) | `ok` |

Omarchy's fifth, `Super+Ctrl+,` (silence toggle), is `koompi toggle silent` and got no chord (O24 asked for the CLI, O12 for the four).
Dismiss takes the toast off the popup layer the way its timeout does, so the right sidebar's history keeps it. This is omarchy's
semantics too (`dismissPopup` keeps history); this shell's swipe-to-dismiss discards outright, which I did not copy: a chord that
deletes history is lossy, and there is no undo.

Descriptions are `Shell: Notifications - …` so they land in the cheatsheet's existing Shell column. Separate file because
`keybinds.lua` is at its `tests/file-length-allow.txt` row; `hyprland.lua` requires it right after `hyprland.keybinds`, so `hl.bind`
is already the Super-release-interrupt wrapper (each chord therefore shows twice in `hyprctl binds`: the described `bindd` and the
transparent interrupt twin, like every other Super chord). Note `tests/test_keybind_descriptions.sh` scans only `keybinds.lua`
and `custom/keybinds.lua`; the new file's descriptions are pinned by `tests/test_toggle_cli.sh` instead (that test is not mine to widen).

### Test
`tests/test_toggle_cli.sh`: `qs` shim on PATH (logs argv; modes live/dead/old) proving 3 switches × 4 verbs, the exact argv each cell
sends, exit 0/1/2/64, bare = toggle, bad args → usage + 64 without reaching qs; four described binds whose IPC names exist in
`Notifications.qml`; loader order; no `Comma` bind in `keybinds.lua`; `luac -p` on both lua files; qmllint (Qt 6) on the three services.
Proof it fails: with the shim's `old` mode mapped to exit 0 in the tool → `FAIL: koompi-toggle silent status: exit 0, want 2`.

## Acceptance 1: test outputs

```
$ nice -n 19 ionice -c 3 bash tests/test_toggle_cli.sh
ok   koompi-toggle: 3 switches x 4 verbs, exit 0/1/2/64 as documented
ok   chords: 4 notification binds described, IPC names match Notifications.qml, loader order right
ok   qmllint: Idle, Hyprsunset, Notifications parse without errors
toggle cli: all checks passed
rc=0

$ bash tests/test_packaged_tools.sh
packaged tools: 29 shipped, 2 excluded, all accounted for
rc=0

$ bash tests/test_keybind_descriptions.sh
keybind descriptions: all 149 binds described or hidden
rc=0

$ shellcheck -x dots/.local/bin/koompi-toggle tests/test_toggle_cli.sh
shellcheck ok
$ luac -p dots/.config/hypr/hyprland/keybinds_notifications.lua dots/.config/hypr/hyprland.lua
luac ok
```

`./tests/run.sh` tail (nice 19):
```
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

82 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
suite rc=0
```

## Acceptance 2: live, this machine

The live shell runs from `~/.config/quickshell/koompi` (a copy, not a symlink; it differs from main in ~60 files, LEAD.md). As J15/J20 did,
I copied the three changed services in; Quickshell's file watcher reloaded them (same pid 702039, `qs -c koompi ipc show` lists
`idle`, `nightlight`, `notifications`). Originals in `/tmp/j31-backup.RtFKM1/services/` (`Idle.qml`, `Hyprsunset.qml` = main;
`Notifications.qml` = main minus the J18 timer guard). Also installed live: `~/.config/hypr/hyprland/keybinds_notifications.lua`,
`~/.config/hypr/hyprland.lua` (backup in `/tmp/j31-backup.RtFKM1/hypr/`), `~/.local/bin/koompi-toggle`. All left in place.

```
$ koompi-toggle night-light status
off
rc=1
$ koompi-toggle night-light
on
rc=0
$ koompi-toggle night-light status
on
rc=0
$ koompi-toggle night-light
off
rc=1
$ koompi-toggle night-light status
off
rc=1

$ koompi-toggle silent status
off
rc=1
$ koompi-toggle silent
on
rc=0
$ koompi-toggle silent status
on
rc=0
$ koompi-toggle silent
off
rc=1
$ koompi-toggle silent status
off
rc=1

$ koompi-toggle night-light on
on
rc=0
$ koompi-toggle night-light off
off
rc=1
```

keep-awake: read only, never flipped (`koompi-toggle keep-awake status` → `off`, rc 1; `systemd-inhibit --list` shows no quickshell
inhibitor). The job says Rithy's session runs with it on; it is off right now. Both states end where they started.

The four notification functions, on real toasts (`notify-send -a J31 …`):
```
$ qs -c koompi ipc --any-display call notifications dismissOne     (no toast on screen)
none
$ qs -c koompi ipc --any-display call notifications dismissOne     (one toast)
ok
$ qs -c koompi ipc --any-display call notifications dismissAll     (two toasts)
ok
$ qs -c koompi ipc --any-display call notifications dismissAll     (nothing left)
none
$ qs -c koompi ipc --any-display call notifications invokeLast     (toast sent with -A default=Open)
ok
notify-send: exit 0 invoked action: 'default'
$ qs -c koompi ipc --any-display call notifications invokeLast     (no toast left)
none
$ qs -c koompi ipc --any-display call notifications showHistory
ok                                                                  (sidebar opened; closed again with `sidebarRight close`)
```
Side effect left behind: six "J31 …" entries in the notification history (the sidebar list). They are not discarded by dismiss, by design.

## Acceptance 3: zig, keybinds.lua length

```
$ cd cli && nice -n 19 ionice -c 3 zig build test --summary all
Build Summary: 3/3 steps succeeded; 3/3 tests passed
test success
+- run test 3 pass (3 total) 6ms MaxRSS:6M
   +- compile test Debug native cached 20ms MaxRSS:55M
rc=0
$ ./zig-out/bin/koompi help | grep toggle
  toggle       Flip keep-awake, night light or notification silencing
$ ./zig-out/bin/koompi help toggle
koompi toggle <keep-awake|night-light|silent> [on|off|toggle|status]

Flip keep-awake, night light or notification silencing

$ wc -l dots/.config/hypr/hyprland/keybinds.lua
447 dots/.config/hypr/hyprland/keybinds.lua
```

## Acceptance 4: hyprctl binds after `hyprctl reload`

Hyprland runs this config as native Lua; `hl.dsp.exec_cmd` binds show as `dispatcher: __lua` with a closure id, not the command
string, so the count is by description.
```
$ hyprctl reload
ok
$ hyprctl binds | grep -c 'description: Shell: Notifications -'
4
	modmask: 64   key: Comma   description: Shell: Notifications - dismiss the newest toast
	modmask: 65   key: Comma   description: Shell: Notifications - dismiss all toasts
	modmask: 72   key: Comma   description: Shell: Notifications - open the newest toast (its default action)
	modmask: 73   key: Comma   description: Shell: Notifications - show history (right sidebar)
```

## Notes for the lead
- `showHistory` opens the sidebar; if a drawer (calendar, to-do, timer, controls) is already open the drawer stays on top. Clearing it
  needs `SidebarRight.qml`, which this job does not own; `Super+N` twice gets there.
- Stop conditions honoured: shell never restarted or killed (pid 702039 throughout), keep-awake never flipped, no `killall`, no sudo,
  `~/.config/koompi/config.json` untouched. The only live changes are the copies listed above plus one `hyprctl reload`.
- A second `qs -p ~/.tmp/koompi-defaults.*/root -n` process (pid 2100671) was running during the job; not mine, left alone.
