# J41 — Branded idle screen before lock (O32)

Branch `j41-branded-idle-screen`, feature commit `c6eac549`.

## What was built

- `modules/koompi/screensaver/Screensaver.qml` (73 lines): the Scope. `open`/`close`/`toggle` on `GlobalStates.screensaverOpen`, `IpcHandler` target `screensaver`, a `Variants` over `Quickshell.screens` whose delegate is a `Loader` active on the bool, and a `Connections` on `GlobalStates.screenLocked` that closes it. `open` is refused while locked: the session-lock surface is composited above every layer, so there would be nothing to see.
- `ScreensaverSurface.qml` (32): the `PanelWindow` per screen. Anchored to all four edges, black, `WlrLayer.Overlay`, namespace `quickshell:screensaver`, `ExclusionMode.Ignore`, keyboard `OnDemand` (takes the keys on map so any key dismisses; compositor binds still pass, so `Super+L` still locks and the lock replaces the layer).
- `ScreensaverContent.qml` (145): what it draws and how it notices a hand. Black rectangle, `CustomIcon` with `koompi-symbolic.svg` colourised `#9a9a9a` at 18 % of the shorter screen edge, a 20 s `Timer` that moves it to a random spot (4 s `InOutSine` drift, kept clear of the clock's corner), `DateTime.time` in the bottom-right at `pixelSize.huge`, a 650 ms fade-in. Dismissal: a 500 ms arming delay (a surface appearing under a stationary pointer gets a pointer-enter that Qt hands over as a hover), then any key, button, wheel, or pointer motion ≥ 8 px from where it settled.
  The split from the surface exists because cage has no layer-shell: the same content item can be hosted in a plain window for the headless capture.
- `GlobalStates.qml`: `screensaverOpen`. `KoompiFamily.qml`: one `PanelLoader` and its import.
- `hypridle.conf`: the 120 s listener before the 300 s lock listener, `on-timeout = qs -c koompi ipc call screensaver open`, `on-resume = … close`, with a comment saying it is the only switch. The lock/DPMS/suspend listeners are untouched.
- `docs/navigation.md`: one row in the entry-point inventory.
- `tests/test_screensaver.sh`: family loads it once, the state bool, the IPC verbs, the `screenLocked` hook, listener order and timeouts, `on-resume` closes it, no `brightnessctl`/`Brightness` in the module, Qt 6 `qmllint` on every file in it.

Keep-awake needs no check: `Idle.qml` holds a Wayland idle inhibitor and a `systemd-inhibit --what=idle:sleep…` block, and hypridle honours the latter itself. The live hypridle's own log shows it: `Idled: rule …` → `Ignoring from onIdled(), inhibit locks: 1` (`/tmp/j15-hypridle-restart.log:301-302`). With keep-awake on the 120 s rule never fires, so nothing calls `open`.

No brightness change anywhere: the black surface is the whole dim (the "No idle dim" note in `hypridle.conf:12-13`); the test greps the module for it.

## Acceptance 1: tests

```
$ nice -n 19 ionice -c 3 bash tests/test_screensaver.sh
ok   qmllint: 3 screensaver files parse without errors
ok   screensaver: loaded once, IPC open/close/toggle, closes on lock, hypridle listener at 120s before the lock at 300s, no brightness writer
rc=0

$ nice -n 19 ionice -c 3 bash tests/test_qml_layering.sh
ok: no service imports a UI package (58 still import qs.modules.common, which is shared)
rc=0

$ nice -n 19 ionice -c 3 bash tests/test_hypridle_logged.sh
skip: live Lock check needs KOOMPI_TEST_LIVE_LOCK=1 (it locks the screen)
rc=0

$ shellcheck -x tests/test_screensaver.sh   # clean
$ bash tests/test_file_length.sh | tail -1
ok: 912 files under cap, 34 allow-listed and not grown
```

qmllint notes (not errors, the same as the existing qmllint tests tolerate): `Failed to import qs…` and the resulting `Unqualified access` on `GlobalStates`, and `Type PanelWindow is not creatable` — qmllint has no qmldir for the shell root; only `^Error` lines fail the test.

Baseline before any change: `83 passed, 3 skipped, 0 failed` (skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh).

Suite after:

```
$ NO_COLOR=1 nice -n 19 ionice -c 3 bash tests/run.sh | tail -2
84 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
(line 114-115: ==> test_screensaver.sh / ok test_screensaver.sh)
```

## Acceptance 2: headless capture

`/tmp/j41-screensaver.png` (1274×687), plus `/tmp/j41-screensaver-drift.png` taken 26 s in.

Method: the worktree's shell root symlinked entry-by-entry into a temp root with a harness `shell.qml`, `qs -p <root>` under `cage` on the wlroots headless backend (`WLR_BACKENDS=headless`, `WAYLAND_DISPLAY`/`DISPLAY`/`HYPRLAND_INSTANCE_SIGNATURE` unset, so nothing touched the live seat or desktop). Same `qs` binary as the live shell.

What did not work, so the lead does not repeat it:
- `Screensaver {}` + `GlobalStates.screensaverOpen = true` under cage: cage 0.3.1 has no `zwlr_layer_shell_v1`, quickshell logs `Failed to initialize layershell integration`, the `PanelWindow` exists (`visible=true size=500x500`) but never maps (`contentItem` stays 0×0, `grabToImage` never calls back, `grim` sees a black output).
- `QT_QUICK_BACKEND=software`: the window maps and the clock renders, but `CustomIcon`'s `ColorOverlay` (a shader) is skipped, and the SVG is black-filled, so the mark is invisible on black. The GL backend (default) renders it.
- What worked: `ScreensaverContent` hosted in a `FloatingWindow` (xdg, which cage fullscreens), `content.grabToImage` at 3 s, GL backend. Harness log:

```
 DEBUG qml: harness: host 1274x687 content 1274x687 armed=true
 DEBUG qml: harness: grabToImage saved=true
 DEBUG qml: harness: grim exit 0          (grim of the cage output agrees: /tmp/j41-E-j41-grim.png)
  INFO: Configuration Loaded
```

Image 1 (3 s): mark centred, `5:29 PM` bottom-right. Image 2 (26 s): mark moved to the lower-left, `5:31 PM`; the drift timer and the `Behavior` both ran.

Dismissal (key, pointer motion past the threshold, the arming delay) is not exercised by the capture: cage headless has no input devices and I will not inject input into the live seat. It is by-inspection only.

The live shell (`qs -c koompi`, pid 702039) has not reloaded this QML, so the live `qs -c koompi ipc call screensaver open` is unverified until `koompi reload`. Its answer today is `Target not found.` (visible in the hypridle log below), which also shows the IPC reaches the live shell.

## Acceptance 3: hypridle parses the conf

Throwaway copy `/tmp/j41-hypridle.conf`: only the 120 s listener, at 3 s; `lock_cmd`/`unlock_cmd`/`before_sleep_cmd`/`after_sleep_cmd = true`, `inhibit_sleep = 0`, no lock/DPMS/suspend listener at all (`grep -E 'lock-session|dpms|suspend|hyprlock'` on the copy matches only its own comment line). Started at 17:30:21 as pid 2414011 alongside the live hypridle (pid 564060, untouched), `ignore_systemd_inhibit = true` so another worker's inhibitor could not hide the result:

```
[LOG] Using config file: /tmp/j41-hypridle.conf
[LOG] Registered timeout rule for 3s:
      on-timeout: echo "J41 on-timeout $(date +%T)"; qs -c koompi ipc call screensaver open
      on-resume: echo "J41 on-resume $(date +%T)"; qs -c koompi ipc call screensaver close
[LOG] found 1 rules
[LOG] Sleep inhibition disabled
[LOG] Idled: rule 558dda170970
[LOG] Running echo "J41 on-timeout $(date +%T)"; qs -c koompi ipc call screensaver open
[LOG] Executing echo "J41 on-timeout $(date +%T)"; qs -c koompi ipc call screensaver open
[LOG] Process Created with pid 2414859
[LOG] Wayland session got locked
J41 on-timeout 17:30:24
Target not found.
[LOG] Resumed: rule 558dda170970
[LOG] Running echo "J41 on-resume $(date +%T)"; qs -c koompi ipc call screensaver close
[LOG] Executing echo "J41 on-resume $(date +%T)"; qs -c koompi ipc call screensaver close
[LOG] Process Created with pid 2537631
J41 on-resume 17:37:38
Target not found.
watcher: 17:37:40 killing throwaway pid 2414011
watcher: done
```

The `Wayland session got locked` line is not mine: the live hypridle's own 300 s rule locked the session at that moment (`/tmp/j15-hypridle-restart.log:647-659`: `Idled` → `Running loginctl lock-session` → `Got Lock from dbus` → `Wayland session got locked`). Rithy had been away since ~17:25:24; that is also why my 3 s rule fired exactly 3 s after its own start. Nothing I ran locks, and the throwaway cannot.

on-resume: the shipped `on-resume` runs whenever the compositor reports activity after the 120 s rule fired. hypridle's idle tracking is `ext_idle_notifier_v1`, seat-level; which surface has focus (the layer or anything else) plays no part in it, so input on the layer resumes it the same as input anywhere. Verified live above: Rithy came back to the seat at 17:37:38 (the session unlocked), the throwaway logged `Resumed` and ran the shipped `on-resume` command verbatim; the watcher then killed only pid 2414011 (the live hypridle 564060 is still running). With the layer up the only difference is which surface receives the input, which is not part of the idle notifier's decision, so the live layer will resume the same way once `koompi reload` has loaded the QML.

## Out of scope, untouched

`Lock.qml`, `LockSurface.qml`, `Idle.qml`, brightness, DPMS/suspend timings, `Config.qml`, any settings UI. `~/.config/koompi/config.json`, the live shell, keep-awake and the live hypridle were not touched.
