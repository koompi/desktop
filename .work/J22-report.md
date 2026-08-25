# J22 report — hypridle as the packaged user unit; Lock handling now readable from the journal

Branch `j22-hypridle-logged` on top of `016057e5`.
Files touched, all inside the contract: `dots/.config/hypr/hyprland/execs.lua` (the hypridle line),
`sdata/install/setups.sh` (`setup_services` only), new `tests/test_hypridle_logged.sh`, this report.
No new unit file and no `hypridle.conf` change: the Arch package ships `/usr/lib/systemd/user/hypridle.service` and it reads `~/.config/hypr/hypridle.conf` as before.

## Choice: (b), the packaged unit

`graphical-session.target` is reached in the KOOMPI session and by the right path:

```
$ systemctl --user is-active graphical-session.target
active
$ systemctl --user show graphical-session.target -p ActiveEnterTimestamp
ActiveEnterTimestamp=Tue 2026-08-25 09:23:21 +07        # Hyprland pid 2268 started 09:23:19
$ systemctl --user show-environment | grep -E "WAYLAND|HYPRLAND_INSTANCE|XDG_CURRENT"
HYPRLAND_INSTANCE_SIGNATURE=efb50993…_1787624599_1188505972
WAYLAND_DISPLAY=wayland-1
XDG_CURRENT_DESKTOP=KOOMPI:Hyprland
```

The target is pulled in by the `execs.lua` line that imports `WAYLAND_DISPLAY`/`HYPRLAND_INSTANCE_SIGNATURE` into the manager and then starts `hyprland-session.target` (`BindsTo=graphical-session.target`), which is what the unit's `ConditionEnvironment=WAYLAND_DISPLAY` and the `hyprctl` in `lock_cmd` need.
`touch-gestures` and `koompi-migrate-notify` already ride the same target, so the enable step follows their pattern (enable without `--now`; starts with the next session).

Why not (a): `systemd-cat` gets the log but keeps a daemon that nothing restarts and that any future re-exec of `hyprland.start` would duplicate.

Double start on reload was checked and does not happen today (`hl.on("hyprland.start")` has exec-once semantics), see Acceptance 1.

`hypridle` finds its logind session with `GetSession("auto")` (`strings /usr/bin/hypridle`), so running under `user@1000.service` instead of `session-3.scope` still resolves to the display session; the live run below confirms it.

## The actual bug (Do 3)

J15 suspected the login-time instance ignored Lock because of the D-Bus env at exec time.
Lock is a *system*-bus signal; `hypridle` connected to the system bus fine (J15 saw it as `:1.28`).
J15's own conclusion stands: every "deaf" observation was the J20 self-unlock inside the 3 s screenshot wait.
There was no env bug to fix; the fix here is that from the next login the question is answerable with `journalctl --user -u hypridle`.

## Acceptance 1: one hypridle before and after `hyprctl reload`

Live session before any change (pid 564060 is J15's hand-started instance, parent 1, stdout on `/tmp/j15-hypridle-restart.log`; the login-time pid 2336 was stopped by J15):

```
before:
564060 hypridle
ok
after:
564060 hypridle
```

With the packaged unit started (transiently, `systemctl --user start`, no file written under `~/.config`):

```
## pgrep before hyprctl reload
564060 hypridle
1061654 /usr/bin/hypridle
ok
## pgrep after hyprctl reload
564060 hypridle
1061654 /usr/bin/hypridle
```

Reload adds nothing either way. The second line is J15's leftover, which I did not kill (not a pid I started; it dies with the session).
Its presence produced a useful line in the unit's log, the reason exactly one instance matters:

```
Aug 25 13:44:20.154057 koompi hypridle[1061654]: [ERR] Another service is already providing the org.freedesktop.ScreenSaver interface
Aug 25 13:44:20.154057 koompi hypridle[1061654]: [ERR] Is hypridle already running?
```

## Acceptance 2: journal lines for `loginctl lock-session`

From the unit in this session (started under the user manager, i.e. the same way the login-time instance will start; fds 1/2 are the journal socket):

```
$ ls -l /proc/1061654/fd/1 /proc/1061654/fd/2
lrwx------ 1 userx userx 64 Aug 25 13:44 /proc/1061654/fd/1 -> socket:[5866070]
lrwx------ 1 userx userx 64 Aug 25 13:44 /proc/1061654/fd/2 -> socket:[5866070]
t0=2026-08-25 13:44:23.234543320
$ bash tests/test_hypridle_logged.sh
ok: hypridle.service logged 'Got Lock from dbus' for loginctl lock-session
exit=0
$ journalctl --user -u hypridle.service --since "$T0" -o short-precise
Aug 25 13:44:23.276655 koompi hypridle[1061654]: [LOG] Got dbus .Session
Aug 25 13:44:23.276655 koompi hypridle[1061654]: [LOG] Got Lock from dbus
Aug 25 13:44:23.276655 koompi hypridle[1061654]: [LOG] Locking with pidof qs quickshell >/dev/null && hyprctl dispatch 'hl.dsp.global("quickshell:lock")' || pidof hyprlock >/dev/null || hyprlock
Aug 25 13:44:23.276655 koompi hypridle[1061654]: [LOG] Executing pidof qs quickshell >/dev/null && hyprctl dispatch 'hl.dsp.global("quickshell:lock")' || pidof hyprlock >/dev/null || hyprlock
Aug 25 13:44:23.279135 koompi hypridle[1061654]: [LOG] Process Created with pid 1061729
Aug 25 13:44:23.298421 koompi hypridle[1061737]: ok
Aug 25 13:44:23.360820 koompi hypridle[1061654]: [LOG] Wayland session got locked
Aug 25 13:44:23.360820 koompi hypridle[1061654]: [LOG] Releasing the sleep inhibitor!
$ loginctl show-session 3 -p LockedHint
LockedHint=yes
```

42 ms from `loginctl lock-session` to `Got Lock from dbus`, 126 ms to the compositor reporting the session locked; no "got unlocked" line followed (J20 holds).
Then `systemctl --user stop hypridle.service` → `Stopped Hyprland's idle daemon.`; `pgrep -a hypridle` back to `564060 hypridle` only; `graphical-session.target.wants/` contains no hypridle symlink (nothing was enabled on this machine).

**Not done: the login-time instance.** That needs the lead to merge, run `systemctl --user enable hypridle` (or `koompi update`, whose `setup_services` does it), log out and in, then run `loginctl lock-session` and paste `journalctl --user -u hypridle -b`.
Until the enable runs, a fresh login with the new `execs.lua` has **no** hypridle at all, which is the one operational risk of route (b).

Rithy's session is locked as of 13:44:23 by this demo; the lock needs the password.

## Acceptance 3: suite and parse

```
$ ./tests/run.sh | tail -3
72 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
$ luac5.4 -p dots/.config/hypr/hyprland/execs.lua && echo parse-ok
parse-ok
$ shellcheck -x -S warning sdata/install/setups.sh; shellcheck -x tests/test_hypridle_logged.sh
(clean; the SC2016 info at setups.sh:168 is pre-existing on main, same exit code there)
```

Baseline was 72 passed, 1-2 skipped; the third skip is the new test in a session without `hypridle.service` running (`skip: no active logind session with hypridle.service running; the live Lock check needs a login`).
It ran live in the demo above.

## What the test checks (`tests/test_hypridle_logged.sh`)

1. `execs.lua` has no `exec_cmd("hypridle…")`.
2. The line that starts `hyprland-session.target` imports `WAYLAND_DISPLAY` with `--systemd` first, in the same command (the unit's `ConditionEnvironment` is evaluated then).
3. `setup_services` (sourced with the installer helpers stubbed) records `systemctl --user enable hypridle`, never `--now`, and only warns when no user manager is there.
4. The packaged unit: output not `null`, `ExecStart` hypridle, `PartOf`/`WantedBy=graphical-session.target`, `Restart=`.
5. In an active logind session with `hypridle.service` running: `loginctl lock-session` → `Got Lock from dbus` in `journalctl --user -u hypridle.service` within 2 s (polled at 100 ms).

## Decisions for the lead

- Step 5 locks the screen on every `./tests/run.sh` once the unit is enabled and the lead is logged in; that is what the contract asked ("skip honestly outside a session"). If that is too much for a per-job gate, an opt-in env guard on that block is a two-line change.
- Packaged (`/etc/skel`) installs never run `setup_services`, so on the ISO nothing enables `hypridle.service` (same gap `touch-gestures` and `koompi-migrate-notify` already have). A `/usr/lib/systemd/user-preset/*.preset` with `enable hypridle.service` in `koompi-hyprland-config` would close it; that package is outside this job's files.
- Pid 564060 (J15's hand-started hypridle, logging to `/tmp/j15-hypridle-restart.log`) is still running; it goes away at logout.

## Round 2: live Lock check is opt-in (`65c98a99`)

The lead's gap: step 5 would lock the screen on every `./tests/run.sh` once the unit is enabled.
It now runs only with `KOOMPI_TEST_LIVE_LOCK=1`; the static checks 1-4 stay unconditional.
The first "Decisions for the lead" bullet above is closed by this.

```
$ bash tests/test_hypridle_logged.sh; echo exit=$?
skip: live Lock check needs KOOMPI_TEST_LIVE_LOCK=1 (it locks the screen)
exit=0
$ KOOMPI_TEST_LIVE_LOCK=1 bash tests/test_hypridle_logged.sh; echo exit=$?     # unit not running here
skip: no active logind session with hypridle.service running; the live Lock check needs a login
exit=0
$ # same test pointed at an execs.lua containing hl.exec_cmd("hypridle"): the static half still fails
1:hl.exec_cmd("hypridle")
FAIL: execs.lua starts hypridle by hand again; the packaged unit owns it
exit=1
$ shellcheck -x tests/test_hypridle_logged.sh && echo clean
clean
$ ./tests/run.sh | tail -3
72 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

No screen lock was triggered in this round (`hypridle.service` inactive, `pgrep -a hypridle` → `564060 hypridle` only).
The live run in Acceptance 2 was done before the guard existed; to repeat it after the next login: `KOOMPI_TEST_LIVE_LOCK=1 bash tests/test_hypridle_logged.sh`.
