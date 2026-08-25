# J15 report: lid lock, bar mode indicators, keybind descriptions

Branch `j15-lid-indicators-keybinds`, three commits on top of `3519a4d2`:

- `f1cb75ec` test(keybinds): every non-hidden bind carries a description
- `568a05e3` feat(session): lock on lid close unless an external monitor is attached
- `05390dca` feat(bar): keep awake, night light and dictation lights on the koompi bar

Files touched, all inside the contract: `dots/.config/hypr/hyprland/keybinds.lua`, new `dots/.local/bin/koompi-lid`,
`modules/koompi/bar/BarContent.qml`, new `modules/koompi/bar/ModeIndicators.qml`, new `tests/test_keybind_descriptions.sh`,
`docs/navigation.md` (two table rows), this report and `.work/J15-bar.png`.
`services/Idle.qml` and `services/Hyprsunset.qml` untouched.

## Judgment calls

- Hidden vs described. The cheatsheet (`services/HyprlandKeybinds.qml`) does not dedupe, so describing the
  `qs ipc call TEST_ALIVE ||` fallback copies would show every chord twice. Fallbacks, the right-Super twin, the
  transparent workspace-number hooks, keycode/keypad duplicates of the number keys, the clipboard half of
  `Ctrl+Print`, the `Alt+F4` nag and the two lid switch binds are marked `-- # [hidden]` with a one-word reason.
  Everything that is a distinct chord a user could learn got a description (XF86 keys, mouse and bracket
  aliases, split ratio, workspace paging/scroll, `Super+T`, the VM submap, `Ctrl+Super+\`). `Super+V` and
  `Super+.` had their description on the fallback only; it moved to the primary bind.
- Kiri dictation state is exposed: `kiri/src/ui/voice.rs` writes `$XDG_RUNTIME_DIR/kiri-voice.pid` while a voice
  session runs and `kiri voice` run again sends SIGUSR1 (stop and paste). ModeIndicators polls the pidfile every
  2 s (same poll as ScreenRecording, paused while locked) and checks the pid against /proc so a stale file does not
  light the mic. Click runs `kiri voice`, which is what pressing the hotkey again does.
- `koompi-lid open` is a documented no-op; clamshell layout is out of scope.

## Acceptance 1: test before and after

Before (at `3519a4d2`, the new test against the old keybinds.lua), tail of 57 lines:

```
dots/.config/hypr/hyprland/keybinds.lua:417: hl.bind("SUPER + T", hl.dsp.exec_cmd(terminal))
dots/.config/hypr/hyprland/keybinds.lua:418: hl.bind("CTRL + ALT + T", hl.dsp.exec_cmd(terminal))
dots/.config/hypr/hyprland/keybinds.lua:430: hl.bind("CTRL + SUPER + Backslash", hl.dsp.window.resize({ x = 640, y = 480, "exact" }))
FAIL: 57 of 147 binds have no description and are not marked [hidden]
exit=1
```

After:

```
keybind descriptions: all 149 binds described or hidden
exit=0
```

(147 + the two lid switch binds.) `luac5.4 -p keybinds.lua` parses; `hyprctl reload` → `ok`.

## Acceptance 2: hyprctl binds after reload

```
$ hyprctl binds -j | jq '[.[] | select(.description=="")] | length'
269
$ hyprctl binds -j | jq length
424
```

Before this job the same query gave 310 of 422. The 269 that remain are not textual binds:

```
$ hyprctl binds -j | jq '(map(select(.description!="")) | map("\(.modmask)/\(.key)") | unique) as $d
    | [.[] | select(.description=="")] | map(select(("\(.modmask)/\(.key)") as $k | $d | index($k))) | length'
158     # transparent release-interrupt twins the hl.bind wrapper adds to every SUPER chord (keybinds.lua:18-27)
```

The other 111 are the `[hidden]` binds (keycode/keypad loops show as empty key with a keycode) plus their own
twins, and the two lid binds:

```
{"locked":true,...,"key":"switch:on:Lid Switch",...,"dispatcher":"__lua","arg":"519"}
{"locked":true,...,"key":"switch:off:Lid Switch",...,"dispatcher":"__lua","arg":"521"}
```

## Acceptance 3: bar screenshot and shell log

`.work/J15-bar.png` (grim -o eDP-1, 12:22): the right indicator group reads `[34] ☕ 🌙 us wifi | pomodoro | clock`
with keep awake and night light both on. Both toggled on through the sidebar quick toggles (ydotool clicks), then
turned off by clicking the bar icons:

```
click ☕ on the bar →  systemd-inhibit --list: no quickshell inhibitor; states.json idle: {"inhibit":false}
click 🌙 on the bar →  hyprctl hyprsunset temperature: 6000
fake dictation      →  echo <pid of a sleep> > $XDG_RUNTIME_DIR/kiri-voice.pid; red mic appears within 2 s
click mic           →  the sleep pid is gone (kiri voice sent it SIGUSR1); mic disappears within 2 s
```

The dictation light was exercised with a synthetic pidfile, not a real `kiri voice` session. `kiri voice` was
run by hand against the same fake pid: exit 0, pid signalled, no window opened.

`qs log -c koompi | tail` after `qs kill -c koompi` + `setsid env QT_QPA_PLATFORM=wayland qs -c koompi` (no
killall; the shell was restarted through its own IPC):

```
  INFO: Configuration Loaded
 DEBUG qml: [Translation] Language changed to en_US
  WARN scene: QML FileView at @services/FirstRunExperience.qml[38:5]: Read of .../first_run.txt failed: File does not exist.
 DEBUG qml: [GlobalFocusGrab] Initialized
  INFO qt.text.font.db: OpenType support missing for "Google Sans Flex", script 32
  WARN scene: QML QQuickImage* at @modules/koompi/background/Background.qml[373:21]: Binding loop detected for property "opacity":
  WARN scene: qs:/home/userx/.config/koompi/plugins/koompi.clock/Widget.qml[-1:-1]: File not found
  WARN quickshell.io.fileview: got operation finished from dropped operation qs::io::FileViewOperation(0x7feb123aa7c0)
 DEBUG qml: [Notifications] File loaded
 DEBUG qml: [MemoryService] ready: provider=local:bge-small-en-v1.5 dim=384
$ qs log -c koompi | grep -i 'ModeIndicators\|BarContent'
(none)
```

All warnings shown are pre-existing and from other files.

## Acceptance 4: test suite

```
$ ./tests/run.sh | tail
==> test_workspace_help_onscreen.sh
  ok test_workspace_help_onscreen.sh
==> test_workspace_icon_migration.sh
  ok test_workspace_icon_migration.sh
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh

57 passed, 0 failed
$ bash tests/test_keep_awake_lid.sh
keep awake lid test passed
$ shellcheck -x dots/.local/bin/koompi-lid tests/test_keybind_descriptions.sh   # clean
$ (cd cli && zig build test); echo $?        # 0
$ (cd installer && zig build test); echo $?  # 2, pre-existing: build.zig:14 'root_source_file' vs zig 0.16.0; installer/ untouched
```

Baseline was 56 passed; the new test makes 57.

## Lid simulation (stop condition: dispatch, not the lid)

`koompi-lid` with stubbed `hyprctl`/`loginctl` on PATH:

```
[internal only]       stub loginctl lock-session          exit=0
[external attached]   koompi-lid: external monitor attached, not locking   exit=0
[hyprctl unusable]    stub loginctl lock-session          exit=0   (unreadable list locks)
[open]                exit=0
[bad arg]             usage: koompi-lid close|open        exit=2
```

Live, via the bind's command:

```
$ hyprctl dispatch 'hl.dsp.exec_cmd("koompi-lid close > /tmp/j15-lid.log 2>&1; echo exit=$? >> /tmp/j15-lid.log")'
ok
$ cat /tmp/j15-lid.log
exit=0
hypridle log:
[LOG] Got Lock from dbus
[LOG] Locking with pidof qs quickshell >/dev/null && hyprctl dispatch 'hl.dsp.global("quickshell:lock")' || pidof hyprlock >/dev/null || hyprlock
[LOG] Executing ...
[LOG] Process Created with pid 564147
[LOG] Wayland session got locked
[LOG] Releasing the sleep inhibitor!
[LOG] Wayland session got unlocked
```

So the lid path does what the contract asks: lid close → `koompi-lid close` → `loginctl lock-session` → hypridle
`lock_cmd` → `quickshell:lock` → session locked. Keep awake wins over suspend by the existing inhibitor
(`test_keep_awake_lid.sh` green above; `koompi-lid` never suspends).

## Findings outside my files (not fixed, lead's call)

1. **Critical, pre-existing: the lock screen unlocks itself ~2.6 s after locking.** Reproduced three times with
   a direct `hyprctl dispatch 'hl.dsp.global("quickshell:lock")'`, timed against hypridle's lock notifier:
   `unlocked after 2.60s`, `2.57s`. Every lock leaves in the system journal:
   `qs[<pid>]: PAM _pam_init_handlers: no default config other` and `fprintd.service: Deactivated successfully`.
   The only unlock path in the code is `LockScreen.qml:41` after a PamContext success
   (`LockContext.qml` password `pam` or `fingerPam` with `configDirectory: "pam"`, `config: "fprintd.conf"`;
   the file exists at `modules/common/panels/lock/pam/fprintd.conf`, content below). Three fingerprints are
   enrolled (`fprintd-list`). Nobody touched the reader or typed. This makes the lid lock, `Super+L`, the session
   menu and the 5-minute idle lock all cosmetic on this machine. Needs the lock owner; I did not touch
   `LockContext.qml`.

   ```
auth    sufficient    pam_fprintd.so
   ```

2. Keep awake flipped itself on once during testing (`states.json` idle.inhibit went true with no click). The
   auto-unlock above runs `Idle.toggleInhibit(true)` when `lockContext.alsoInhibitIdle` is set
   (`LockScreen.qml:113`, set by `LockSurface.qml:460 tryUnlock(root.ctrlHeld)`), which is the likely route.
   Also `states.json` said `{"inhibit":true}` at session start while no inhibitor existed; a second qs instance
   (`qs -p .../welcome.qml`, pid 384956 at the time) shares `Persistent` and can rewrite the file.
3. I restarted hypridle by PID (old 2336 → new 564060, logging to `/tmp/j15-hypridle-restart.log`) while
   chasing finding 1, on a hypothesis that turned out wrong (the lock did engage; it just unlocked before my
   screenshot). Same config, same session; it is running normally. Its log is what produced the trace above.
4. `hyprctl binds -j` is valid JSON on Hyprland 0.56.2; the comment in `services/HyprlandKeybinds.qml:20-23`
   about 0.56.0 may be stale.

## Live machine state

Installed for the demonstration and left in place: `~/.config/hypr/hyprland/keybinds.lua`,
`~/.config/quickshell/koompi/modules/koompi/bar/{BarContent,ModeIndicators}.qml`, `~/.local/bin/koompi-lid`.
Originals of the two overwritten files are in `/tmp/j15-backup.uLQ06D`. Keep awake and night light are back to
off (their state before the job); `kiri-voice.pid` removed; `~/.config/koompi/config.json` untouched.
The screen was locked/unlocked several times by the simulations; it is unlocked now (finding 1).
