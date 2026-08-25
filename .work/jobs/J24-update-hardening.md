# J24 — `koompi update` hardening: single run, stay awake, free space, restart advice, lock-aware reload (O02 O10 O21)

`.work/OMARCHY-AUDIT.md` rows O02, O10, O21. J11 (merged) rewrote the routes and the defaults merge in
`dots/.local/share/koompi/libexec/update`; this job adds the guards omarchy has around the upgrade itself.
Read `update` end to end first: `update_packaged` (line ~533), `update_from_git` (~618), `reload_session` (~133),
`stop_processes` (~64), and the five tests `tests/test_update_*.sh`, `test_reload_idempotent.sh`,
`test_install_reloads_shell.sh`, `test_snapshot_pre_update.sh` (they shim the binaries; extend that pattern).

## Files you own
- `dots/.local/share/koompi/libexec/update`
- `dots/.local/bin/koompi-reload`
- new `tests/test_update_guards.sh`; `.work/J24-report.md`

## Do
1. (O02) Single run: take an exclusive `flock` on `$XDG_RUNTIME_DIR/koompi-update.lock` (fall back to
   `${TMPDIR:-/tmp}` with the uid in the name) around both routes; a second `koompi update` prints "another
   koompi update is running (pid N)" and exits 1 without touching pacman or git.
2. (O02) Stay awake: run the upgrade under `systemd-inhibit --what=sleep:idle:handle-lid-switch --who=koompi-update
   --why=...` when `systemd-inhibit` exists (same three classes `services/Idle.qml` uses, for the same lid reason);
   without it, warn once and continue.
3. (O02) Free space: before `pacman -Syu` / `git pull`, require 2 GiB free on `/` (packaged) or on the checkout's
   filesystem (git) — omarchy uses 10 GiB, cite why you pick less or keep 10; `--yes` does not override it, a
   clear `die` with the number does.
4. (O10) After a packaged upgrade: compare `uname -r` with the newest installed kernel (`/usr/lib/modules/*` with a
   `vmlinuz`), and check `/proc/$(pidof Hyprland)/exe` for ` (deleted)`; if either, print a "reboot needed" line
   (`warn`) and skip the shell reload's "shell restarted" ok in favour of that advice. Do not reboot.
5. (O21) `reload_session` and `koompi-reload`: before killing `qs`, ask the shell whether the session is locked
   (find the real IPC target for `GlobalStates.screenLocked` in `modules/koompi/lock/` and `services/` and cite
   it). If locked, refuse: "session is locked; unlock and run `koompi reload`". `koompi-reload` also drops
   `killall` for the same pid-based `stop_processes` logic `update` has (copy it; the two scripts stay separate).
6. Tests: `tests/test_update_guards.sh` shims `flock`/`pacman`/`systemd-inhibit`/`df`/`uname`/`qs`/`hyprctl` on
   PATH like the existing update tests do and proves: second run refused; inhibit wrapper used; low space dies
   before pacman; kernel mismatch prints the reboot line; locked session refuses the reload.

## Acceptance
1. Paste the new test's output and `./tests/run.sh` tail (baseline + 1).
2. Paste a real `koompi update --dry-run` on this machine showing the lock taken, the inhibit line, the free-space
   line, and the lock check, in that order.
3. `shellcheck -x` on both scripts: empty.
4. `wc -l` of `update`: it is outside `tests/test_file_length.sh`'s walk today (no extension); keep it under 800
   and say what it is.

## Out of scope
- `sdata/install/update.sh` (the git route's pull, J11's), `koompi-snapshot`, `koompi-migrate`.
- Anything under `sdata/dist-arch/`.

## Stop conditions
- No real `pacman -Syu`, no reboot, no killing the live shell outside the shimmed tests; dry-run only on this machine.
- If the locked-session query has no IPC surface today, stop and report the exact file that would need one.
