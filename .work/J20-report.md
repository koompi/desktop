# J20 report — the lock screen "unlocks itself"

Branch `j20-lock-self-unlock`, commits `67b08c65` (fix), `600051b8` (test).
Two live locks of Rithy's session were needed: one before the fix (13:12:40, unlocked after 3.6 s) and one after (13:25:04, held; still locked at the time of writing, see the end).
Both `LockContext.qml` and `LockScreen.qml` live at `modules/common/panels/lock/`, not `modules/koompi/lock/` as the contract names them; those are the files I changed.
`LockSurface.qml`, `Lock.qml` and `services/Idle.qml` needed no change.

## Verdict, in one paragraph

The unlock is a real fingerprint match, not a PAM fall-through.
The only path that ends the lock is `LockContext.unlocked`, and the instrumented reproduction shows it fired from the fingerprint `PamContext` completing with `PamResult.Success` (`result=0`) 3.0 s after fprintd said "Place your finger on the fingerprint reader".
pam_fprintd returns `PAM_SUCCESS` from exactly one line, `str_equal(data->result, "verify-match")` (fprintd 1.94.5 `pam/pam_fprintd.c:590-592`), i.e. only when fprintd reports that an enrolled finger matched.
The journal line `PAM _pam_init_handlers: no default config other` is libpam 1.7.2 looking for `<configDirectory>/other` after it has already read `fprintd.conf` successfully (`libpam/pam_handlers.c:515-545`: the service file sets `read_something=1`, the missing `other` only logs, and `PAM_ABORT` needs both to be missing); it is noise, not a cause.
The same stack driven in isolation never succeeds without a finger: a `qs -p` probe of the fingerprint PamContext with the same directory ran the full 30 s timeout and completed `Error` (`Permission denied (code 6)`, libpam's sanity check for a stack with no positive result), `fprintd-verify` ran 3 × 15 s with no match, and the journal shows two locks that stayed up for minutes with the reader re-armed every 31.5 s and never matched (12:35:30 → 12:38:12, 12:39:28 → 12:41:56).
With the hardened stack live, a lock held for 35 s with `LockedHint=yes` at 0.5 s, 30 s and 35 s while fprintd's only verdict was the 30 s timeout (`verify-no-match`) followed by the re-arm.
What I cannot prove from here is whose finger it was; every "self-unlock" measured today happened while someone was at the machine and ended in a `verify-match`, so the question for Rithy is whether a finger rested on the reader (Lenovo 21NSS03D00, Synaptics 06cb:0123 "press" sensor) in the seconds after each lock.

## Do 1 — reproduction (before), timed

Live shell pid 702039 (`qs -c koompi`, instance `3p1fx3abkt`), with the two lock files temporarily instrumented with `console.log` (originals backed up to `/tmp/j20-backup.xHk6jW`, reloaded by Quickshell's file watcher).
`T0` is the `hyprctl dispatch` moment.

```
T0=13:12:40.783836444 dispatch lock
ok
hypridle (/tmp/j15-hypridle-restart.log, stamped by tail -F):
13:12:40.880687998 [LOG] Wayland session got locked
13:12:40.881840537 [LOG] Releasing the sleep inhibitor!
13:12:44.504809664 [LOG] Wayland session got unlocked        <- 3.62 s after locked
13:12:44.526644629 [LOG] Inhibited sleep with fd 10
qs log (instrumented):
13:12:40.813 [J20] GlobalStates.screenLocked=true
13:12:40.817 [J20] tryFingerUnlock configured=true active=false
13:12:40.889 [J20] WlSessionLock.secure=true locked=true
13:12:41.031 [J20] fingerPam message="Place your finger on the fingerprint reader" responseRequired=false
13:12:44.039 [J20] fingerPam completed result=0 (Success=0 Failed=1 Error=2)
13:12:44.041 [J20] LockContext.unlocked(0) alsoInhibitIdle=false stack=LockScreen.qml:102 | LockContext.qml:291
13:12:44.492 [J20] unlockDelayTimer fired -> screenLocked=false
13:12:44.493 [J20] WlSessionLock.secure=false locked=true
13:12:44.494 [J20] WlSessionLock.locked=false secure=false screenLocked=false
journal:
Aug 25 13:12:40.823009 koompi qs[799643]: PAM _pam_init_handlers: no default config other
qs children (pgrep -P 702039): 799643 appears 13:12:40.891, gone 13:12:44.101  <- the PAM subprocess
monitors: eDP-1 ws1 -> ws2147483646 at 13:12:41.208 (lock push) -> ws1 at 13:12:44.201 (restore)
loginctl show-session 3 -p LockedHint: "no" throughout (the shell never set it; fixed below)
```

No reload (`LockScreen destroyed` was not logged until my later file change), no compositor `finished`, no password attempt (`tryUnlock` never logged), no `Quickshell.screens` change.
J15's numbers (2.57 s, 2.60 s) were measured the same way against hypridle.

## Do 2 — mechanism evidence

- Quickshell 0.2.1 (`7511545e`) `src/services/pam/subprocess.cpp`: `pam_start_confdir(config, user, &conv, configDir, &handle)`, then `pam_authenticate`; `PAM_SUCCESS` → `Success`, `PAM_AUTH_ERR` → `Failed`, `PAM_MAXTRIES` → `MaxTries`, anything else → `Error`. `qml.cpp` refuses to start (`start()` returns false, nothing completes) when the directory or file is missing. `configDirectory: "pam"` resolves relative to the QML file (`context->resolvedUrl`), confirmed by the probe: `configDirectory resolved to: /tmp/j20/probe/pam`.
- libpam 1.7.2 `pam_handlers.c:476-545`: service file read → `read_something=1`; `other` missing → `pam_syslog(LOG_ERR, "_pam_init_handlers: no default config %s")` and nothing else. `pam_dispatch.c:310-312`: a stack that ends without a positive impression is forced to `PAM_PERM_DENIED`. Arch's `/etc/pam.d/other` is irrelevant here: with a confdir libpam only looks inside that directory (`_pam_open_config_file`, line 314-329).
- Isolated probe of the shipped stack (`qs -p`, `QT_LOGGING_RULES=quickshell.service.pam.debug=true`, same relative `pam` directory, reader untouched):

```
[probe 0.51s] message: "Place your finger on the fingerprint reader"
[probe 30.55s] message: "Verification timed out"
quickshell.service.pam.subprocess: Error while authenticating: "Permission denied" (code 6)
[probe 30.56s] completed: 2 (Success=0 Failed=1 Error=2 MaxTries=3)
journal: 13:05:49.053 qs[728385]: PAM _pam_init_handlers: no default config other   (same line, no unlock)
```

- `fprintd-verify` × 3, 15 s each, nobody touching: `rc=124` (timeout) every time, no `verify-match`.
- `gdbus monitor --system --dest net.reactivated.Fprint` works unprivileged and shows fprintd's verdicts; during the after-fix lock the only ones were `VerifyStatus('verify-no-match', true)` at each 30 s timeout.
- Journal cadence during J15's session: `_pam_init_handlers` every 31.5 s from 12:35:30 to 12:38:12 and from 12:39:28 to 12:41:56 = pam_fprintd's 30 s timeout + the 1.5 s re-arm, i.e. locks that stayed locked for minutes with the reader armed and never matched. The single-line locks (12:34:12, 12:42:43, 12:44:30, 12:46:02) ended within 30 s.
- `strace` is not installed and was not needed: the config path is printed by the probe and by the subprocess debug line (`Starting pam session ... in dir "/tmp/j20/probe/pam"`).
- `/etc/pam.d/system-auth` is clean (`pam_fprintd` was removed from it, see `system-auth.bak.pre-fix`); `sudo` and `greetd` still carry `pam_fprintd`, which is unrelated to the lock.

## Do 3 — the change

`pam/fprintd.conf` now ends its auth stack with `auth required pam_deny.so`, and `pam/other` denies all four types, so the directory is self-contained and the journal line is gone (verified live: no `PAM` line in the journal since 13:25:00, versus one per lock before).
`LockContext.tryUnlock` and `tryFingerUnlock` check `start()`: a config that cannot be opened is a failed attempt ("Password check is unavailable. Check the PAM configuration.") or `FingerprintEnum.Error`, instead of a password field disabled forever behind `unlockInProgress` or an icon inviting a touch nothing listens for.
`failureMessage` is now a plain property set by `authFailed()`, which is the single place a password attempt ends short of success, and it clears `alsoInhibitIdle` (so does `reset()`); this closes J15's finding 2 on the shell side (the Ctrl+Enter keep-awake flag could outlive a failed attempt and ride along on a later fingerprint unlock). `Idle.qml` did not need a change.
pam_fprintd's timeout now completes as `Failed` (the deny line) rather than `Error`; the info message "Verification timed out" is recognised and re-arms quietly instead of showing "Fingerprint not recognized" for 1.5 s.
`LockScreen` sets logind's `LockedHint` via `busctl call ... /org/freedesktop/login1/session/auto ... SetLockedHint b true|false` on lock and unlock; without it acceptance item 4 cannot be observed (the before-run shows `LockedHint=no` for the whole lock).
Nothing was weakened: no `pam_permit` in the shipped stack, the password path is untouched, `/etc/pam.d` untouched, no fingerprints touched.

## Do 4 — `tests/test_lock_pam.sh`

Static checks on the stack shape and the shell's gating, then `qs -p` probes against temp directories that never load `pam_fprintd` (fprintd and the reader are not touched).
Cannot be automated: a successful password or fingerprint unlock (needs the real credential); the password stack is the system's `/etc/pam.d/login`, which this repo does not ship.
`pam_permit` appears only as the positive control in a temp directory so a silent probe cannot pass.

Against `HEAD~2` (old config, old logic):

```
$ git archive HEAD~2 | tar -x -C $OLD; cp tests/test_lock_pam.sh $OLD/tests/; (cd $OLD && bash tests/test_lock_pam.sh)
ok   ... (nothing; first check fails)
FAIL: pam/other is missing (libpam looks it up for every service in the directory)
exit=1
$ # old logic with the new pam/ files copied in:
ok   pam/: fprintd.conf is sufficient pam_fprintd + required pam_deny; other denies all four types
FAIL: LockContext ignores pam.start() returning false (field stays disabled forever)
exit=1
```

After:

```
$ bash tests/test_lock_pam.sh
ok   pam/: fprintd.conf is sufficient pam_fprintd + required pam_deny; other denies all four types
ok   LockContext: unlock gated on PamResult.Success twice, start() failures handled; LockScreen sets LockedHint
ok   missing config: start() is false and nothing completes
ok   shipped stack with an unloadable pam_fprintd: completes without success (completed=1)
ok   sufficient-only stack with an unloadable module: libpam's own fallback also denies (completed=2)
ok   positive control: the probe reports success when libpam grants it
ok   journal: only the directory without 'other' logged '_pam_init_handlers: no default config other'
exit=0   (1.4 s)
```

`shellcheck -S warning tests/test_lock_pam.sh`: clean.

## Do 5 — after the fix, live

Fixed files copied into `~/.config/quickshell/koompi/modules/common/panels/lock/` (Quickshell reloaded, same pid 702039, `diff -r` against the repo tree clean).
Rithy was told in chat 25 s ahead not to touch the reader.

```
T0=13:25:04.983959989 dispatch lock
ok
13:25:05.497170157 +0.5s LockedHint=yes
13:25:35.005771576 +30s  LockedHint=yes
13:25:40.023582552 +35s  LockedHint=yes
hypridle:
13:25:05.078401969 [LOG] Wayland session got locked
13:25:05.079566300 [LOG] Releasing the sleep inhibitor!
(no "got unlocked")
fprintd (gdbus monitor --system --dest net.reactivated.Fprint):
13:25:05.058 VerifyFingerSelected ('any',)
13:25:35.053 VerifyStatus ('verify-no-match', true)      <- 30 s timeout, VerifyStop
13:25:36.566 VerifyFingerSelected ('any',)               <- 1.5 s re-arm
13:26:06.551 VerifyStatus ('verify-no-match', true)
13:26:08.063 VerifyFingerSelected ('any',)
13:26:38.037 VerifyStatus ('verify-no-match', true)
13:26:39.490 VerifyFingerSelected ('any',)
journal since 13:25:00: no PAM lines
```

I cannot unlock it: the password is Rithy's, and a fingerprint has to be a finger.
Rithy unlocked it 2 min 22 s later, with the password:

```
13:27:10.963 VerifyFingerSelected ('any',)                <- 4th re-arm
13:27:26.699 VerifyStatus ('verify-no-match', true)       <- 15.7 s in, not a timeout: VerifyStop after the
                                                             password PamContext succeeded and stopFingerPam()
                                                             killed the fingerprint subprocess (child 916221 gone 13:27:26.72)
13:27:27.143 [LOG] Wayland session got unlocked           <- hypridle, 470 ms unlockDelayTimer later
13:27:27.194 LockedHint=no                                <- SetLockedHint false (children 918044/918048 = keyring unlock + busctl)
```

No `verify-match` in the 142 s the session was locked with the reader armed.
Fingerprint unlock after the change is therefore not yet exercised; the stack armed and re-armed exactly as before the change, so Rithy verifying one fingerprint unlock closes that.
Monitor logs: `/tmp/j20/repro-after/`.

## Acceptance 5 — gates

`./tests/run.sh` (61 tests now):

```
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh

60 passed, 1 failed
failed: test_packaged_tools.sh
```

`test_packaged_tools.sh` fails identically on `HEAD~2`: `FAIL: dots/.local/bin/koompi-lid is neither in _tools nor in _tools_excluded in koompi-shell/PKGBUILD` (J15's new binary versus J13's list; both files outside mine, not touched).
`test_lock_pam.sh` is `ok` inside the run (line 64 of the log).

qmllint (Qt 6, `-I` with the shell root symlinked as `qs`), warnings/errors before → after: `LockContext.qml` 23 → 24, `LockScreen.qml` 32 → 33.
Each new one is an "Unqualified access" on a line I added (`Translation.tr(...)` in `tryUnlock`, `GlobalStates.screenUnlockFailed` in `authFailed`, `GlobalStates.screenLocked` in the `setLockedHint` call), the same category as all existing warnings in both files; no errors.

## Out of scope, reported only

- Hyprlock fallback, hypridle timings, J15's third finding: untouched. Hyprland's own log is empty because `debug:disable_logs = true`, so the compositor never records lock events; enabling it would have saved the instrumented run.
- `loginctl show-session -p LockedHint` was "no" throughout every lock before this change; anything that relied on it (the contract's own oracle) was reading nothing.
- J15's finding 2, second half (`states.json` `idle.inhibit` true at session start, a second `qs -p welcome.qml` sharing `Persistent`): outside my files.
- `qs log -f` dies with SIGABRT when killed with SIGTERM (coredump at 13:12:49 was mine); harmless, Quickshell CLI.
- Nothing to propose for `/etc/pam.d`: the lock's stacks never read it except `login` for the password, which is stock.

## Live state

`~/.config/quickshell/koompi/modules/common/panels/lock/{LockContext.qml,LockScreen.qml,pam/fprintd.conf,pam/other}` are the committed versions; originals (pre-J20, identical to `HEAD~2`) in `/tmp/j20-backup.xHk6jW`.
Probe files, fetched sources and logs: `/tmp/j20/`.
