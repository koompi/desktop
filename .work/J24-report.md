# J24 report — `koompi update` hardening (O02 O10 O21)

Branch `j24-update-hardening`, commit `1f074fd9` (code + test) and the report commit after it.
Files touched: `dots/.local/share/koompi/libexec/update`, `dots/.local/bin/koompi-reload`, new `tests/test_update_guards.sh`.

## What landed

- O02 lock: `main` re-execs itself under `flock -n -E 75 -o $XDG_RUNTIME_DIR/koompi-update.lock` (fallback `${TMPDIR:-/tmp}/koompi-update-<uid>.lock`).
  Not a bash fd: a bash fd is inherited by every spawned process, and the restarted `qs` would hold the lock until logout; `-o` closes it before exec, so the lock lives in the `flock` process and dies with the run.
  The child writes its pid into the file; the loser prints `another koompi update is running (pid N)` and exits 1 before `is_packaged` runs `pacman -Qq`.
- O02 awake: `systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block --who=koompi-update --why='KOOMPI update in progress' tail --pid=$$ -f /dev/null`, held for the whole run.
  Same three classes as `services/Idle.qml:57`, for its reason (logind weighs the lid against `handle-lid-switch` alone).
  `tail --pid` ends by itself if the run is SIGKILLed; the EXIT trap kills the holder by pid otherwise.
  Verified on this machine that killing `systemd-inhibit` by pid takes its child with it (systemd 261 forks with PDEATHSIG): probe left 0 inhibitors and no orphan.
  Without `systemd-inhibit`: one `warn`, continue.
- O02 space: 2 GiB on `/` (packaged) or on the checkout's filesystem (git, and the packaged-to-git fallback), checked before `confirm`, the snapshot and `pacman -Syu` / `./setup update`.
  2 GiB, not omarchy's 10: KOOMPI targets 64 GB eMMC school laptops where 10 GiB free is often not there while an upgrade fits; the floor only has to cover the download, pacman's own `CheckSpace` still guards the install step.
  `--yes` does not waive it; the `die` names both numbers.
- O10: `check_restart_needed` runs right after `pacman -Syu` (and the AUR helper): newest `/usr/lib/modules/*/vmlinuz` by `sort -V` vs `uname -r`, and `/proc/$(pidof -s Hyprland)/exe` ending in ` (deleted)`.
  `main` prints one `warn "reboot needed: ..."` after the reload; `reload_session` drops its `ok "shell restarted"` when a reason is set. Nothing reboots.
- O21: `session_locked` in both scripts. Lock query surface, cited:
  `modules/koompi/lock/Lock.qml` and `LockSurface.qml` have no `IpcHandler`; the only lock IPC is `modules/common/panels/lock/LockScreen.qml:150-159` (`lock.activate`/`focus`, no state getter).
  What the shell does publish is `LockScreen.qml:133-140` `setLockedHint`: on every `screenLocked` change it calls `busctl ... org.freedesktop.login1.Session SetLockedHint`, so `loginctl show-session <id> -p LockedHint --value` is the shell's answer, and it is readable from ssh where the qs socket's seat session is not ours (every session of the uid is asked).
  `hyprlock` (`lock.useHyprlock`) sets no hint, so `pgrep -x hyprlock` is the second check.
  Live: `loginctl show-session 3 -p LockedHint --value` → `no` on this machine right now.
  Packaged route: `reload_session` warns `session is locked; the shell was not restarted. Unlock and run 'koompi reload'` and leaves qs alone; the update itself still succeeds.
  Git route: refused whole before the pull (`die`), because `./setup update` owns that reload and cannot skip it (`sdata/lib/common.sh reload_session`, `setup parse_install_options` has no `--no-reload`); both files are outside this job.
  `koompi-reload`: refuses with exit 1 under a lock, and the bare `killall -w -q global-menu-daemon qs quickshell || true` is replaced by a copy of `update`'s `stop_processes` (pgrep first, one name at a time).

## Incident during acceptance (fixed, covered by the test)

The first cut called `run_locked "$@"` after the option loop had `shift`ed the arguments away, so the re-exec'd child ran with no `--dry-run`.
Two `koompi update --dry-run` invocations therefore ran the git route for real against `~/workspace/koompi-desktop`:
`git pull --ff-only` (`Already up to date`, one new tag `iso-koompi-2026.08.25-x86_64` fetched), `git submodule update` (no-op), then `sudo -v` with no terminal, which triggered the fingerprint prompt, timed out and died with `could not obtain sudo`.
Nothing past `sudo_start` ran; the checkout's reflog shows only the lead's own merges; no inhibitor was left behind.
Fix: `main` snapshots `argv=("$@")` before parsing and re-execs with it.
`tests/test_update_guards.sh` step 1 fails on the old behaviour (the dry run would either reach `pacman -Syu` or die on the unanswered `confirm`).

## Acceptance

### 1. Test output and suite tail

```
$ bash tests/test_update_guards.sh
update guards test passed
```

Proof it can fail: with `UPDATE=` pointed at `main`'s script → `FAIL: dry run is missing the lock, inhibit or free-space line`; with `RELOAD=` pointed at `main`'s `koompi-reload` → the locked-session step fails (rc 1).

```
$ ./tests/run.sh
==> test_update_guards.sh
  ok test_update_guards.sh
...

80 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Baseline at main was 79 passed, 3 skipped, 0 failed; now 80/3/0.

### 2. Real `koompi update --dry-run` on this machine

`$XDG_DATA_HOME` points the CLI's `updateHelper` (`cli/src/main.zig:152`) at this worktree's `libexec/update`; everything else is the live machine (route from-git, checkout `~/workspace/koompi-desktop`).
Lock taken → inhibit line → free-space line → lock check, in that order:

```
$ XDG_DATA_HOME=/tmp/j24-cli.9IIDID koompi update --dry-run    # $XDG_DATA_HOME points the CLI at this worktree's libexec/update
  -> lock taken: /run/user/1000/koompi-update.lock (pid 1837755)
     $ systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block --who=koompi-update --why=KOOMPI update in progress tail --pid=1837755 -f /dev/null

==> Updating from /home/userx/workspace/koompi-desktop
  -> route: from-git (the checkout owns the installed config)
  -> free space on /home/userx/workspace/koompi-desktop: 173.8 GiB (needs 2 GiB)
  -> session lock: unlocked (logind LockedHint); ./setup update may restart the shell
[... ./setup update --dry-run from the live checkout: pull skipped "(dry run: nothing is pulled)", every step printed with $, nothing run ...]
==> Reloading the running session
     $ hyprctl reload
     $ killall -w -q global-menu-daemon
     $ killall -w -q qs
     $ killall -w -q quickshell
  -> would restart the shell

==> Done
  KOOMPI is up to date.
  Your ~/.config/hypr/custom/ overrides were left untouched.

==> Done
  KOOMPI is up to date (from-git route). koompi-health reports on the session.
rc=0
```

After the run: `/run/user/1000/koompi-update.lock` holds the child's pid (the lock itself is released with the `flock` process), `systemd-inhibit --list` shows 0 `koompi-update` inhibitors, `~/workspace/koompi-desktop` status clean, no `~/.koompi-dots-backup/20260825-15*` created.

### 3. shellcheck

```
$ shellcheck -x dots/.local/share/koompi/libexec/update dots/.local/bin/koompi-reload; echo rc=$?
rc=0
```

Empty. Two pre-existing SC2016 infos on the jq programs (`MERGE_JQ_PROGRAM`, `_rows_jq`, present at main) are now silenced with a directive naming why (`$old/$new/$user` are jq variables).

### 4. Length

```
$ wc -l dots/.local/share/koompi/libexec/update
783 dots/.local/share/koompi/libexec/update
$ awk 'END { print NR }' dots/.local/share/koompi/libexec/update   # how test_file_length counts
784
```

It is a bash script with no extension under `dots/.local/share/koompi/libexec/`, so `cap_for` in `tests/test_file_length.sh` skips it today (694 at main, 784 now, under 800).
J26 adds `dots/.local/share/koompi/libexec/*` at the bash cap of 400 with an allow-list row; an allow-listed file may only shrink, so J26's row must be taken from this branch's count, not main's.

## Notes for the lead

- Test deviation: `flock` is not shimmed. A shim answering "busy" would only test the message; the test runs a real first update blocked inside the `pacman` shim and a real second one, and asserts the refusal pid is alive and the shim log did not grow.
- Test hook: `KOOMPI_UPDATE_MODULES_DIR` replaces `/usr/lib/modules` for the kernel check (a container running the suite has no modules tree). The replaced-Hyprland case needs no hook: the test runs a copy of `sleep` and deletes its binary, so `/proc/<pid>/exe` really ends in ` (deleted)`.
- Comment rule: my additions are one-line WHYs. The pre-existing prose paragraphs in `update` (header, dump_defaults, merge) fall under `~/.claude/rules/comments.md` but are J11's text; I left them rather than rewrite 700 lines under a three-row contract. Rithy's call.
- Pre-existing, not mine, seen while running: `sdata/install/files.sh:216` says `ok backed up 75 file(s)` in a dry run that backs up nothing; `tests/test_reload_idempotent.sh`'s fake `qs` leaves an orphaned `sleep 30` after cleanup (same pattern I hit; my test reaps its sleep on TERM).
- Stop conditions honoured: no real `pacman -Syu`, no reboot, no live shell killed (the only reload runs were shimmed); the one real git pull was the incident above, a no-op.

## Round 2 — J26 ratchet: guards moved to `libexec/update-lib.sh`

Rebased onto main (`1a0b8492`); on that tree `test_file_length.sh` failed with `update grew from 695 to 784`.
Commit `0e59bcea` moves the messages, `run`/`stop_processes`/`count_shells` and the guards (`run_locked`, `stay_awake`, `require_free_space`, `session_locked`, `check_restart_needed`) into new `dots/.local/share/koompi/libexec/update-lib.sh` (110 lines, sourced, `# shellcheck shell=bash`).
`update` sources it next to itself (`dirname "$(readlink -f "${BASH_SOURCE[0]}")"`, so the CLI's `$XDG_DATA_HOME` symlink still resolves to the real file) and exits 1 with `update-lib.sh is missing next to this script; reinstall with ./setup update` if it is not there.
`koompi-reload` looks in `$XDG_DATA_HOME/koompi/libexec`, `~/.local/share/koompi/libexec`, `/usr/lib/koompi`, the order `updateHelper` uses in `cli/src/main.zig:151-165`, and dies naming all three when none has it; its own copies of `stop_processes`/`session_locked` are gone.
The allow-list was not touched.

### Line counts (`awk 'END { print NR }'`, as `test_file_length.sh` counts)

```
dots/.local/share/koompi/libexec/update: 695
dots/.local/share/koompi/libexec/update-lib.sh: 110
dots/.local/bin/koompi-reload: 36
```

### Packaging: libexec is NOT shipped as a tree

- `sdata/dist-arch/koompi-shell/PKGBUILD:110-111`: `install -Dm755 ".../dots/.local/share/koompi/libexec/update" "$pkgdir/usr/lib/koompi/update"` — one file, by name; `update-lib.sh` will not be in the package.
- `tests/test_packaged_tools.sh` pins only `_tools`/`_tools_excluded` against `dots/.local/bin` (lines 24-27, 48-53); nothing there covers `libexec`, so the suite cannot catch this.
- Consequence on KOOMPI OS: `/usr/lib/koompi/update` dies at start (`dump-defaults`/`merge-config` subcommands too, since the source line runs first) and `koompi reload` dies on the third lookup, until the PKGBUILD also installs `update-lib.sh` to `/usr/lib/koompi/update-lib.sh` (one more `install -Dm644` line at `PKGBUILD:111`). `sdata/dist-arch/` is out of this job's scope; not touched.
- Git installs are fine: `sdata/install/files.sh` copies `dots/` whole, so `~/.local/share/koompi/libexec/update-lib.sh` lands with `update`.
- Missing-lib behaviour, exercised: `XDG_DATA_HOME= HOME=/nonexistent koompi-reload` → `koompi reload: update-lib.sh not found in ${XDG_DATA_HOME}/koompi/libexec, ~/.local/share/koompi/libexec or /usr/lib/koompi; reinstall with ./setup update`, rc 1; a copy of `update` alone in `/tmp` → `koompi update: update-lib.sh is missing next to this script; reinstall with ./setup update`, rc 1.

### Checks

```
$ shellcheck -x dots/.local/share/koompi/libexec/update dots/.local/share/koompi/libexec/update-lib.sh dots/.local/bin/koompi-reload; echo rc=$?
rc=0
$ bash tests/test_update_guards.sh
update guards test passed            # 5 consecutive runs, all rc=0
$ bash tests/test_file_length.sh
ok: 909 files under cap, 34 allow-listed and not grown
$ ./tests/run.sh
81 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

The first suite run after the split failed `test_update_guards.sh` once: `koompi-reload` backgrounds `setsid … &` and the test read the shim log the instant the script exited. The test now polls for that line (up to 2 s); five standalone runs and the suite are green.

Real `koompi update --dry-run` through the CLI against the split scripts, same four lines in the same order (rc 0, 0 inhibitors left):

```
  -> lock taken: /run/user/1000/koompi-update.lock (pid 1976577)
     $ systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block --who=koompi-update --why=KOOMPI update in progress tail --pid=1976577 -f /dev/null

==> Updating from /home/userx/workspace/koompi-desktop
  -> route: from-git (the checkout owns the installed config)
  -> free space on /home/userx/workspace/koompi-desktop: 178.3 GiB (needs 2 GiB)
  -> session lock: unlocked (logind LockedHint); ./setup update may restart the shell
```
