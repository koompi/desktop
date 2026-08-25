# J32 report — OSD from the command line, battery-low hooks, one TUI launch convention (O23, O29, battery row)

Branch `j32-osd-cli-battery-tui`. Files touched, all in the owned list: `OnScreenDisplay.qml` (237 → 273), new
`indicators/OsdMessage.qml` (74), `services/Battery.qml` (114 → 122), `dots/.local/bin/koompi-hook` (usage block only),
new `koompi-osd` (53), new `koompi-launch-tui` (40), `koompi-shell/PKGBUILD` (pkgrel 5 → 6, `_tools` + `koompi-launch-tui`,
`koompi-osd`), `cli/src/main.zig` (one row, help, `command_names`, three completions, one assertion),
`scripts/launch_sysmon.sh`, `hyprland/rules.lua` (231 → 234), `docs/agents/hooks.md` (two rows, counts), new
`tests/test_osd_cli.sh` (148). `keybinds*.lua` untouched: the sysmon bind's class regex `'sysmon-scratch'` is an unanchored
`test()` in `toggle_app_scratchpad.sh:18`, so it still finds `TUI.sysmon-scratch` and no bind change is needed.

## What was built

### O23: `osd` IpcHandler + `koompi-osd`
- `OnScreenDisplay.qml`: target `osd`, `show(icon, message, progress, duration): string` → sets `messageIcon/Text/Progress`,
  `currentIndicator = "message"`, `triggerOsd(duration)`; returns `ok`. `hide()` too. `progress` < 0 means no bar, else
  0..100 clamped and stored as 0..1 like the value indicators. `triggerOsd(duration)` now takes an optional ms; the three value
  indicators call it bare and get `Config.options.osd.timeout` as before (`osdTimeout.interval` picks `messageDuration` only
  when > 0). Same `PanelWindow`, same timer, same hover-to-dismiss (the test pins the file to one `PanelWindow`).
- `indicators/OsdMessage.qml`: the value indicator's pill (shadow, `colLayer0`, `rounding.full`), sized to its text
  (min `osdWidth`, text wraps at 3× `osdWidth`), icon optional, bar + percent only when `progress >= 0`.
- It is rendered by a second `Loader` in the same column with `sourceComponent: OsdMessage { icon: root.messageIcon … }`
  rather than a row in the `indicators` table: a file loaded by URL cannot see `root`'s properties, an inline component can
  (that is also why `OsdValueIndicator` subclasses only read singletons). The table's Loader gets
  `active: currentIndicator !== "message"`, so exactly one of the two is alive.
- `koompi-osd [-i ICON] [-m TEXT] [-p 0..100] [-d MS]` (long forms too): needs at least one of `-i`/`-m`, validates
  `-p` (integer 0..100) and `-d` (positive integer), sends `qs -c koompi ipc --any-display call osd show -- ICON TEXT PROGRESS
  DURATION` (`-1`/`0` defaults; the `--` is accepted by qs's parser, checked live against `idle inhibit`, and keeps a message
  starting with a dash out of it). Exit 0 shown, 2 when qs exits 255 (no instance) or the shell does not answer `ok`
  ("Target not found." from a shell that predates the handler, or qs's argument-count error 109 — the case this machine's
  live shell is in right now), 64 usage. Same codes as `koompi-toggle`.
- `koompi osd` registered beside `toggle` (helper `koompi-osd`), in the help's Desktop block, `command_names` and the three
  completion strings; `findCommand("osd").?.helper` asserted.

### Battery hooks
- `Battery.qml`: `fireHook(event)` → `Quickshell.execDetached(["koompi-hook", event, "--",
  "KOOMPI_HOOK_BATTERY_PERCENT=<int>"])`, called at the end of `onIsLowAndNotChargingChanged` (`battery-low`) and
  `onIsCriticalAndNotChargingChanged` (`battery-critical`), after the toast and the sound, so it fires exactly when they do:
  once per crossing, not on the way up, not again while under the line. Notification and sound untouched.
- `koompi-hook`: both events in the `Events KOOMPI fires today` block. There is no allowed list in the tool: the event is only
  validated by the `^[A-Za-z0-9][A-Za-z0-9_-]*$` regex (`koompi-hook:45`), and the only tests naming `koompi-hook`
  (`test_update_{route,transcript,guards}.sh`) shim the binary, so the second stop condition did not apply.
- `docs/agents/hooks.md`: two rows, "two" → "four", and the guard note now says the shell's `execDetached` has no
  `command -v` guard (a missing tool is one warning in the shell log).

### O29: `koompi-launch-tui`
- `koompi-launch-tui <app-id> <command...>`: validates the id (`^[A-Za-z0-9][A-Za-z0-9_.-]*$`), picks the first of
  `wezterm foot kitty alacritty` on PATH — the order of `terminal` in `hyprland/variables.lua:11` (`konsole kgx uxterm xterm`
  dropped: no class flag) — spells each one's class flag (`wezterm start --class`, `foot --app-id`, `kitty --class`,
  `alacritty --class … -e`), and `exec koompi-launch --id <app-id> -- <terminal…>` so the window lands in `app.slice`
  (`dots/.local/bin/koompi-launch`, J21). Exit 64 usage, 69 no terminal. Only wezterm is installed here; the other three rows
  are covered by the shim test, not by a real terminal.
- `rules.lua`: three rules on `^TUI\.` (float, center, the portal chooser's `monitor_w*0.60 × monitor_h*0.65`), placed before
  the sysmon rules so the named rule's size wins; sysmon's class is now `^(TUI\.sysmon-scratch)$` (workspace + size; float and
  center come from the generic rule). Its comment said `SUPER + SHIFT + Escape`; the bind is `SUPER + backslash`, fixed.
- `launch_sysmon.sh` → `exec koompi-launch-tui sysmon-scratch sh -c 'btop || htop || top'`.

### Test
`tests/test_osd_cli.sh`: qs / koompi-launch / wezterm / foot shims on PATH logging argv. koompi-osd: 5 good rows (every
spelling, defaults, `--`, a message starting with `-`), dead (255) / old ("Target not found.") / no-handler (109) → 2 with the
stderr hint, 10 bad-argument rows → usage + 64 without reaching qs, `--help`. koompi-launch-tui: the sysmon row's exact argv,
a second app-id, foot fallback with wezterm absent (`TOOL_PATH` narrows PATH), exit 69 with none, 4 bad rows → 64, terminal order
pinned to `variables.lua`. Wiring: IPC target + typed `show` signature, `OsdMessage` rendered, one `PanelWindow`, TUI rules,
sysmon still pinned, no bare `sysmon-scratch` rule left, keybinds.lua's regex, `luac -p rules.lua`, both hook events in
Battery.qml / koompi-hook usage / hooks.md, the cli row; qmllint (Qt 6) on OnScreenDisplay, OsdMessage, Battery.
Proof it fails: with `"$progress" "$duration"` swapped in the tool →
`FAIL: koompi-osd -i check -m hello -p 40: shim called with '… -- check hello 0 40', want '… -- check hello 40 0'`.

## Acceptance 1: test outputs

```
$ nice -n 19 ionice -c 3 bash tests/test_osd_cli.sh
ok   koompi-osd: argument table, exit 0/2/64, -- before the values
ok   koompi-launch-tui: TUI.<app-id> class, terminal order, exit 0/64/69
ok   wiring: IPC target, TUI rules, sysmon scratch, battery hook events, cli row
ok   qmllint: OnScreenDisplay, OsdMessage, Battery parse without errors
osd cli: all checks passed
rc=0

$ nice -n 19 ionice -c 3 bash tests/test_packaged_tools.sh
packaged tools: 31 shipped, 2 excluded, all accounted for
rc=0

$ nice -n 19 ionice -c 3 bash tests/test_file_length.sh | tail -1
ok: 912 files under cap, 34 allow-listed and not grown

$ shellcheck -x dots/.local/bin/koompi-osd dots/.local/bin/koompi-launch-tui dots/.local/bin/koompi-hook \
    dots/.config/hypr/hyprland/scripts/launch_sysmon.sh tests/test_osd_cli.sh      → clean
$ luac -p dots/.config/hypr/hyprland/rules.lua                                      → ok
```

qmllint (Qt 6, `-I <link to shell root as qs>`): 0 `Error` lines in all three files; the warnings are the unresolved `qs.*`
imports every file in the tree gets under this invocation plus the `Unqualified access` those cause (`Appearance`, `Config`),
same as `OsdValueIndicator.qml` on main (0 errors, same warning classes).

`./tests/run.sh` tail (nice 19). The branch point already had one test more than J31's baseline (82), so 84 = base 83 + 1:
```
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

84 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

## Acceptance 2: live OSD — unverified (stop condition)

The live shell (pid 702039, runs from `~/.config/quickshell/koompi`) predates the handler, and installing the three QML files
into that tree (the J31 route: file watcher hot-reload, same pid) was denied by the session's permission classifier, twice,
as was `install` into `~/.local/bin`. Per the job's first stop condition no second `qs` instance was started. So the
`osd` IpcHandler is proven by qmllint and the shim test only; the live call and `/tmp/j32-osd.png` wait for the next
`koompi reload` after merge. What the tool does against today's shell, run from the worktree:
```
$ PATH=$PWD/dots/.local/bin:$PATH koompi-osd -i check -m "hello" -p 40
ipc: The following arguments were not expected: check hello 40 0
Run with --help for more information.
koompi-osd: no answer from the shell: qs exit 109 (shell older than this tool?)
rc=2
$ koompi-osd -p 40
koompi-osd: nothing to show: give -i or -m
Usage: koompi-osd [-i ICON] [-m TEXT] [-p 0..100] [-d MS]
…
rc=64
```
A backup of the live files was taken before the denial and is unused: `/tmp/j32-backup.3tmBi8/` (OnScreenDisplay.qml,
Battery.qml, rules.lua, launch_sysmon.sh) — nothing in `~/.config` or `~/.local/bin` was changed by this job.

## Acceptance 3: live sysmon window

`koompi-launch` is not on this machine's PATH (`~/.local/bin` has no copy, `/usr/bin` has only `koompi-session`), so the
`Super+\` bind cannot work here today regardless of this job; the widget was opened with the branch's script and the branch's
`dots/.local/bin` prefixed on PATH, with the live (pre-J32) `rules.lua`, hence not floating and not on `special:sysmon`:
```
$ PATH=$PWD/dots/.local/bin:$PATH dots/.config/hypr/hyprland/scripts/launch_sysmon.sh &
$ hyprctl clients -j | jq '.[] | select(.class|startswith("TUI."))'
{
  "class": "TUI.sysmon-scratch",
  "title": "bash",
  "pid": 2537401,
  "floating": false,
  "workspace": { "id": 2147483646, "name": "2147483646" },
  "size": [1908, 1188],
  "initialClass": "TUI.sysmon-scratch"
}
$ cat /proc/2537401/cgroup
0::/user.slice/user-1000.slice/user@1000.service/app.slice/app-sysmon\x2dscratch-542454272.scope
```
Class and scope are the contract; the float/centre/special placement is the new `rules.lua`, which is proven by `luac -p` and
the test's rule greps and takes effect at the next `hyprctl reload` with the file installed. The window was closed (`kill
2537401`) right after the capture.

## Acceptance 4: zig, line counts

```
$ cd cli && nice -n 19 ionice -c 3 zig build test --summary all
test success
+- run test 3 pass (3 total) 5ms MaxRSS:4M
   +- compile test Debug native success 240ms MaxRSS:148M
$ zig fmt --check src/main.zig → ok
$ ./zig-out/bin/koompi help | grep osd
  osd          Show a line on the on-screen display
$ ./zig-out/bin/koompi help osd
koompi osd [-i ICON] [-m TEXT] [-p 0..100] [-d MS]

Show a line on the on-screen display
```

| file | lines | cap |
| --- | --- | --- |
| `onScreenDisplay/OnScreenDisplay.qml` | 273 | 400 |
| `onScreenDisplay/indicators/OsdMessage.qml` | 74 | 400 |
| `services/Battery.qml` | 122 | 400 |
| `dots/.local/bin/koompi-hook` | 87 | 400 |
| `dots/.local/bin/koompi-osd` | 53 | 400 |
| `dots/.local/bin/koompi-launch-tui` | 40 | 400 |
| `koompi-shell/PKGBUILD` | 140 | — |
| `cli/src/main.zig` | 361 | 600 |
| `hyprland/scripts/launch_sysmon.sh` | 3 | 400 |
| `hyprland/rules.lua` | 234 | 300 |
| `docs/agents/hooks.md` | 63 | — |
| `tests/test_osd_cli.sh` | 148 | — |

## Notes for the lead
- Needed after merge, not done here: `koompi reload` (or install the shell files) to get the `osd` target live, and
  `koompi-launch` + the two new tools on PATH (`koompi-shell` 1.1-6 ships all three).
- A bind for a generic TUI is not needed: `koompi-launch-tui` is called from scripts; the sysmon bind keeps working unchanged.
- `koompi-launch-tui`'s foot/kitty/alacritty rows are shim-tested only (only wezterm is installed here).
- `docs/agents/hooks.md` beyond "the events table row": the two sentences counting events ("two" → "four") and the guard
  paragraph, since they would otherwise contradict the rows.
- Stop conditions honoured: shell never restarted or killed (pid 702039 throughout), no sudo, no second qs instance,
  `~/.config/koompi/config.json` untouched, nothing written under `~/.config` or `~/.local/bin`.
