# J30 report — `koompi update` transcript, `koompi doctor --last-update`, firmware advice (O28 O31)

Branch `j30-update-transcript`. Files touched: `dots/.local/share/koompi/libexec/update` (687 lines, was 694),
`dots/.local/share/koompi/libexec/update-lib.sh` (186), `dots/.local/bin/koompi-health` (236),
new `tests/test_update_transcript.sh` (201).

## What changed

- O28 transcript. `main` in `libexec/update` re-execs itself through `transcript_reexec` (update-lib.sh) before the
  lock, so a refused second run is on record too. The outer process runs
  `script -qefc "<bash> <self> <argv>" $XDG_STATE_HOME/koompi/logs/update-<YYYYmmdd-HHMMSS>.log` with
  `KOOMPI_UPDATE_TRANSCRIPT` set; the inner run sees the variable and does not recurse (it is unset together with
  `KOOMPI_UPDATE_LOCKED` once the lock is held, so children never inherit it). After `script` returns the outer
  appends `koompi update: exit <rc> at <date>` to the file, prints `transcript: ~/.local/state/koompi/logs/...` as the
  last line, and exits with the inner's status. `--dry-run` skips the whole thing. Before each run the newest 9
  transcripts are kept (`prune_transcripts`), so the directory never holds more than 10; other logs in that directory
  (`health.log`, ...) are never touched. A second run inside the same second waits one second for a fresh stamp so the
  file name order stays the chronological order (both pruning and the doctor rely on that).
  When stdout is not a terminal the outer exports `NO_COLOR=1`, because `script` hands the inner run a pty and it would
  otherwise colour a piped stdout.
- O28 diagnosis. `koompi-health --last-update` (what `koompi doctor --last-update` runs) prints the newest transcript's
  path, its exit line (or "no exit line; the run was interrupted, or is still going"), and one `diagnosis:` line per
  matched row of a fixed table (`FAILURE_PATTERNS`): pacman conflicts, mirror 404, keyring/signature, no space
  (pacman, kernel ENOSPC and our own 2 GiB refusal), "another koompi update is running", git merge conflict / local
  changes. Otherwise `diagnosis:  no known failure pattern`. Exit status is 0 only when the last update ended with
  exit 0, so it works as a gate. The help text says transcripts are never uploaded. `koompi-health` also got a usage
  (`-h/--help`) and rejects unknown options with exit 2; its `LOG_DIR` now honours `XDG_STATE_HOME` like the update
  engine does (it used to hard-code `$HOME/.local/state`).
- O31 firmware. After `pacman -Syu` (and the AUR helper) succeeds on the packaged route, `firmware_advice` runs when
  `fwupdmgr` exists: `fwupdmgr refresh` (network; failure ignored, offline is fine, exit 2 "metadata fresh" is fine),
  then `fwupdmgr get-updates --no-unreported-check --no-metadata-check --no-remote-check`. Exit 0 prints
  `firmware updates are available; apply them with 'koompi update --firmware'`; exit 2 (fwupd's "nothing to do")
  prints `firmware: up to date`; anything else is a warning with fwupdmgr's last line. Dry run prints
  `would check for firmware updates` and calls nothing. `koompi update --firmware` runs `fwupdmgr update` through
  `run` (so `--dry-run --firmware` only prints it) and nothing else: no lock, no inhibitor, no transcript, no pacman.
  Without `fwupdmgr` it dies with `it comes with the fwupd package: sudo pacman -S fwupd`.
- To make room in `update` (allow-listed at 695, may not grow) the duplicate `check_restart_needed` /
  `REBOOT_REASON` block was deleted; update-lib.sh already defined the identical function and `update` sources it.

### fwupdmgr flags, verified

`fwupdmgr` is not installed on this machine (`pacman -Si fwupd`: extra/fwupd 2.1.7-1), so `--help` could not be
run here. The flags were verified in the fwupd 2.1.7 source (`src/fu-util.c`, option table at lines 5438-5510):
`--no-unreported-check` "Do not check for unreported history", `--no-metadata-check` "Do not check for old metadata",
`--no-remote-check` "Do not check if download remotes should be enabled". `fu_util_perhaps_refresh_remotes` prompts
"Update now? (Requires internet connection)" when metadata is 30+ days old unless `--no-metadata-check` or
`--assume-yes`; `get-updates` calls it. `fwupdmgr refresh` has no prompt and returns `FWUPD_ERROR_NOTHING_TO_DO`
(exit 2, "Metadata is up to date; use --force to refresh again") when recently refreshed, so it is called without
`--force`. The man page (`man.archlinux.org/man/fwupdmgr.1`, 2.1.7) documents exit 2 as "commands that have no
actions but were successfully executed". `--offline` in fwupdmgr means "schedule for next reboot" and is not what the
brief meant by offline-safe; the three `--no-*-check` flags plus a tolerated `refresh` failure are.

### script(1) ownership

`pacman -Qo /usr/bin/script` → `util-linux 2.42.2-1`. util-linux is in Arch's `base` meta-package and `flock`
(already required by `run_locked`) comes from the same package, so `script` is guaranteed wherever the lock is.
`transcript_reexec` still dies with `script (util-linux) is required` rather than silently running unlogged.

## Acceptance

### 1. New test and suite tail

```
$ nice -n 19 ionice -c 3 bash tests/test_update_transcript.sh
update transcript test passed
```

The existing update tests now go through the real `script(1)` (they are not dry runs and do not shim it):
`test_update_guards` passed, `test_update_route` rc=0, `test_update_pull_honesty` rc=0, `test_snapshot_pre_update`
rc=0, `test_config_merge` rc=0, `test_migrate_pending_run` passed, `test_file_length` "ok: 910 files under cap,
34 allow-listed and not grown".

Suite tail (`nice -n 19 ionice -c 3 ./tests/run.sh`):

```
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

82 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

Baseline 81 passed / 3 skipped / 0 failed; now 82 / 3 / 0 (+1, the new test). The three skips are the pre-existing
ones (no live compositor / hypridle / bench).

### 2. Dry run on this machine, and the doctor against a fixture

`koompi update --dry-run` through the real CLI with the worktree's engine (`KOOMPI_UPDATE_HELPER`), `--yes` added
so `confirm` does not read a terminal. This machine is a from-git install, so the route was git; no transcript and
no firmware check apply to a dry run either way. Head, tail and the log directory before/after (unchanged: same
seven files, same sizes, same mtimes):

```
### log dir before
total 232
drwxr-xr-x 2 userx userx   4096 2026-08-24 19:34 .
-rw-r--r-- 1 userx userx   1508 2026-08-05 11:07 health.log
-rw-r--r-- 1 userx userx    438 2026-08-24 19:34 hooks.log
-rw-r--r-- 1 userx userx   7392 2026-07-21 23:24 hypridle.log
-rw-r--r-- 1 userx userx 169187 2026-08-03 01:11 quicklook.log
-rw-r--r-- 1 userx userx     71 2026-07-21 19:55 README
-rw-r--r-- 1 userx userx   4275 2026-08-22 10:32 stacking.log
-rw-r--r-- 1 userx userx  17566 2026-08-23 07:16 wallpaper.log

### KOOMPI_UPDATE_HELPER=<worktree>/libexec/update koompi update --dry-run --yes
  -> lock taken: /run/user/1000/koompi-update.lock (pid 2095795)
     $ systemd-inhibit --what=sleep:idle:handle-lid-switch --mode=block --who=koompi-update --why=KOOMPI update in progress tail --pid=2095795 -f /dev/null

==> Updating from /home/userx/workspace/koompi-desktop
  -> route: from-git (the checkout owns the installed config)
  -> free space on /home/userx/workspace/koompi-desktop: 186.8 GiB (needs 2 GiB)
  -> session lock: unlocked (logind LockedHint); ./setup update may restart the shell
[... 150 lines of ./setup update --dry-run ...]
==> Done
  KOOMPI is up to date (from-git route). koompi-health reports on the session.
rc=0

### log dir after
total 232
drwxr-xr-x 2 userx userx   4096 2026-08-24 19:34 .
-rw-r--r-- 1 userx userx   1508 2026-08-05 11:07 health.log
-rw-r--r-- 1 userx userx    438 2026-08-24 19:34 hooks.log
-rw-r--r-- 1 userx userx   7392 2026-07-21 23:24 hypridle.log
-rw-r--r-- 1 userx userx 169187 2026-08-03 01:11 quicklook.log
-rw-r--r-- 1 userx userx     71 2026-07-21 19:55 README
-rw-r--r-- 1 userx userx   4275 2026-08-22 10:32 stacking.log
-rw-r--r-- 1 userx userx  17566 2026-08-23 07:16 wallpaper.log
```

`koompi doctor --last-update` against a fixture transcript (CRLF, as `script` writes it) in a throwaway
`XDG_STATE_HOME`:

```
$ XDG_STATE_HOME=/home/userx/.tmp/tmp.Psf1GGJRPJ koompi-health --last-update
transcript: /home/userx/.tmp/tmp.Psf1GGJRPJ/koompi/logs/update-20260825-170211.log
ended:      koompi update: exit 1 at 2026-08-25 17:02:40
diagnosis:  pacman conflict: read the error: lines above it, remove or rename the file or package it names, then run koompi update again
rc=1
```

### 3. shellcheck and line counts

```
$ shellcheck -x dots/.local/share/koompi/libexec/update dots/.local/share/koompi/libexec/update-lib.sh dots/.local/bin/koompi-health tests/test_update_transcript.sh
shellcheck rc=0            (no output)
$ wc -l
  687 dots/.local/share/koompi/libexec/update        (allow-listed at 695; was 694)
  186 dots/.local/share/koompi/libexec/update-lib.sh (cap 400)
  236 dots/.local/bin/koompi-health                  (cap 400)
  201 tests/test_update_transcript.sh
```

`tests/file-length-allow.txt` was not touched (not in the job's file list); the 695 row still holds since the file
only shrank. The row could be ratcheted to 687.

### 4. Help

`libexec/update --help`:

```
18:Every real run keeps a transcript in ~/.local/state/koompi/logs/update-<stamp>.log
19:(newest 10 kept, never uploaded); 'koompi doctor --last-update' reads it back.
22:  -n, --dry-run    Print what would happen and change nothing (no transcript)
25:      --firmware   Run 'fwupdmgr update' interactively and nothing else
```

`koompi-health --help`:

```
koompi doctor - read-only health check of the KOOMPI desktop session

Usage:
  koompi doctor                 Check the compositor, shell, portals and tools;
                                exits 1 when a core check fails
  koompi doctor --last-update   Print the newest 'koompi update' transcript's
                                path, how it ended, and one line per known
                                failure pattern found in it; exits 1 unless
                                that update finished with exit 0
  koompi doctor -h, --help      This message

Transcripts are ~/.local/state/koompi/logs/update-<stamp>.log (newest 10 kept).
They are never uploaded anywhere; hand the file to whoever is helping you yourself.
```

Caveat: the installed `koompi` CLI intercepts `--help`/`-h` itself (`cli/src/main.zig:300`, `commandHelp`) and prints
the usage string from its `commands` array, so `koompi doctor --help` today prints `koompi doctor` and
`koompi update --help` prints `koompi update [--dry-run] [--yes] [--no-reload]`. Out of scope for this job; the
rows to update in `cli/src/main.zig:13-15`:

```
.usage = "koompi update [--dry-run] [--yes] [--no-reload] [--firmware]"
.usage = "koompi doctor [--last-update]"
.usage = "koompi health [--last-update]"
```

`koompi-health --help` and `libexec/update --help` (what the shell's own `usage` prints on a bad option) already show
the new flags.

## Out of scope, untouched

`koompi-migrate`, `koompi-snapshot`, `koompi-reload`, `sdata/install/update.sh`, `cli/src/main.zig`,
`sdata/dist-arch/**`, `tests/file-length-allow.txt`. No `pacman -Syu`, `fwupdmgr update`, or reboot was run on this
machine; the real runs in the tests go through shims for pacman, sudo, fwupdmgr and `script`, and `flock` stays real.
J33 adds the `fwupd` dependency; `cmd_firmware` names the package until then.
