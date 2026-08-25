# J05 report — split sdata/install/setups.sh by concern (AUDIT D5)

Branch `j05-split-setups-sh`, based on main `86c616f5`.
Three commits, in order: `08ea94ff` the split, `6eb210ff` the allow-list row, `cbeb877a` a dry-run fix found while running Acceptance 4 (judgeable alone; drop it if unwanted).
Files touched: `sdata/install/setups.sh`, new `sdata/install/setups/*.sh` (9 files), `tests/file-length-allow.txt` (granted by addendum 3), and four tests outside the ownership list (see Decisions, first item).
`setup`, `.github/workflows/installer.yml`, `sdata/lib/common.sh` and `sdata/install/update.sh` are untouched.
No sudo, no non-dry-run install, nothing killed; the dry run left no backup directory behind (`ls ~/.koompi-dots-backup/20260825-15*` → no matches).

## Decisions the lead should look at

1. **Four tests outside "Files you own" got a one-line path change each.**
   `test_session_list.sh`, `test_cursor_theme.sh`, `test_install_reloads_shell.sh` and `test_sysdefaults.sh` grep `sdata/install/setups.sh` for text (a constant, a function body, a path) that the job moves into `setups/session.sh`, `desktop.sh`, `globalmenu.sh` and `system.sh`.
   Without the change they fail, and Acceptance 5 (unchanged count) cannot be met; no other job file names those tests.
   Each edit is the `SETUPS=`/grep path only; the assertions are unchanged.
   They are inside the split commit so the tree passes at every commit.
   The tests that *source* `setups.sh` (`test_suspend_hook`, `test_portal_backends`, `test_hypridle_logged`, `test_zig_build_abort`) needed nothing: `setups.sh` still defines every function by sourcing the new files.

2. **Addendum 2 cannot be satisfied as stated; the workflow needs one more glob.**
   `shellcheck -x` reads sourced files to resolve names but reports nothing found *inside* them, not even a parse error.
   Proof against a scratch copy, CI's exact command, cwd = scratch root:

   ```
   [1] SC2086 + SC2154 (unquoted undefined var) added to sdata/install/setups/globalmenu.sh:36
   $ shellcheck -x setup install.sh sdata/install/*.sh
   rc=0                                       <- not reported
   [1b] same file named explicitly
   $ shellcheck -x -s bash sdata/install/setups/globalmenu.sh
   In sdata/install/setups/globalmenu.sh line 36:
       step "Global menu daemon (rust)" $undefined_var
                                        ^------------^ SC2154 (warning): undefined_var is referenced but not assigned.
                                        ^------------^ SC2086 (info): Double quote to prevent globbing and word splitting.
   rc=1
   [2] stray `fi` appended to sdata/install/setups/python.sh
   $ shellcheck -x setup install.sh sdata/install/*.sh
   rc=0                                       <- a parse error in a sourced file is not reported either
   [3] sdata/install/setups/cli.sh deleted
   $ shellcheck -x setup install.sh sdata/install/*.sh
   In sdata/install/setups.sh line 10:
   source "$_SETUPS_DIR/cli.sh"
          ^-------------------^ SC1091 (info): Not following: setups/cli.sh: openBinaryFile: does not exist
   rc=1
   ```

   So the directives are in place and do their job (case 3 shows CI follows them; every `run_setups` call resolves without SC2154), but the only thing that makes CI *lint* the new files is naming them.
   The workflow is not mine to edit; the change is one line in `.github/workflows/installer.yml:41`:

   ```
   -          shellcheck -x setup install.sh sdata/install/*.sh
   +          shellcheck -x setup install.sh sdata/install/*.sh sdata/install/setups/*.sh
   ```

   Until that lands, the job's own step-4 command (which names them) is the check: it is clean, output below.

3. **`source=setups/<name>.sh` needed `# shellcheck source-path=SCRIPTDIR`.**
   shellcheck 0.11.0 resolves `source=` against the cwd only; with the lead's relative form and no `source-path`, CI's command from the repo root reported SC1091 "Not following: setups/_guards.sh ... does not exist" nine times.
   The `source-path=SCRIPTDIR` directive at the top of `setups.sh` makes the lead's exact form resolve from any cwd (verified from `/tmp` as well as the repo root).
   The alternative was repo-root-relative paths like `setup` uses (`source=sdata/install/setups/_guards.sh`), which would also work from the root but nowhere else.

4. **Pre-existing bug fixed in a separate commit (`cbeb877a`): `./setup install --dry-run` aborted with rc=1 at "Assistant memory" on main.**
   On a machine with no `~/.cache/koompi/src/koompi-agent-memd`, `memd_source` prints the `git clone` (dry run) and returns the path it would have created; `setup_agent_memory` then calls `run_in_dir` on it, `cd` fails and `die` ends the dry run before portals, toolkit defaults, the login session, the files step, the global menu and the services ever print.
   Severity: medium — every fresh-machine dry run is cut short and exits 1, which reads as "the install is broken".
   The fix is four lines in `setups/agent_memory.sh`: under `DRY_RUN` with no source directory, print `would build in <dir> once it is cloned` and carry on; the non-dry-run path is byte-identical.
   The split commit is verbatim and its Acceptance 4 diff (below) is empty *including* the abort; the fixed run is shown after it.
   This is the one place the branch changes what a step prints; it is out of the job's stated scope, so it is on its own commit.

5. **Two comments were repointed, otherwise bodies are verbatim.**
   The suspend hook that `sudo_write` installs says `See setup_suspend_hook in sdata/install/setups.sh`; it now says `setups/system.sh`.
   `agent_memory.sh` said "Same shape as setup_shell_services below it"; it now says "in system.sh".
   Sorted-line diff of old body vs the concatenated new files shows only those two lines and the nine new file headers.

6. **Acceptance 1's "no file over 200" is missed by 4 lines in `system.sh` (204).**
   The contract was written at 630 lines; J14 added `setup_low_ram_defaults` (51 lines) and the job pins it to `system.sh` alongside `setup_services` (61 lines after J22).
   Addendum 3 sets the live cap at 400; everything is under it.
   Moving `setup_shell_services` (21 lines) elsewhere would get under 200 but contradicts the job's file map, so I kept the map.

## Stop condition 1: variables set outside common.sh

Every `$UPPER` referenced in the new files, minus those assigned in the new files themselves, and where each is set:

```
DRY_RUN                sdata/lib/common.sh
HOME                   (environment)
OS_GROUP_ID            sdata/lib/distro.sh
PATH                   (environment)
REPO_ROOT              setup             <- the only one from `setup` (setup:15, readonly, before the source at setup:27)
RUST_MIN               sdata/lib/common.sh
SYSTEM_MANIFEST        sdata/lib/common.sh
TMPDIR                 (environment)
VENV_DIR               sdata/lib/common.sh
XDG_BIN_HOME           sdata/lib/common.sh
XDG_CACHE_HOME         sdata/lib/common.sh
XDG_CONFIG_HOME        sdata/lib/common.sh
XDG_DATA_HOME          sdata/lib/common.sh
ZIG_MIN                sdata/lib/common.sh
```

`REPO_ROOT` is still visible: `source` runs in the caller's shell, so a file sourced from `setups/` sees exactly what `setups.sh` saw, and the new files do not use `REPO_ROOT` to find each other (`setups.sh` locates them from `BASH_SOURCE`).
Evidence in the dry run: `uv pip install ... -r /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/uv/requirements.txt` and the seven `sudo install -Dm644 <REPO_ROOT>/sdata/dist-arch/koompi-sysdefaults/...` lines resolve from inside `python.sh` and `system.sh`.
`setup` did not need editing.

## What was done (Do 1–5)

- Do 1: read `setups.sh`, `common.sh`, `setup:15-27`, `setup:224-240`, `update.sh:152` (`run_update` also calls `run_setups`), and every test that names `setups.sh`.
- Do 2: nine files under `sdata/install/setups/`, bodies extracted by line range from the original with `sed -n`, in the file map the job gives; the `readonly` constants went with the functions that read them (`LOCAL_AI_*`, `SEARXNG_PORT` → `ai.sh`; `MEMD_REPO_URL`, `MEMD_SRC` → `agent_memory.sh`; `KOOMPI_CURSOR_*` → `desktop.sh`).
- Do 3: `setups.sh` is the header, `_SETUPS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/setups"`, nine `source` lines each with its directive, `unset _SETUPS_DIR`, and `run_setups` unchanged. `run_setups`, `setup_global_menu`, `setup_services` keep their names; `setup:226`, `setup:237`, `setup:240`, `update.sh:152` call them unchanged.
- Do 4: every new file starts with `# shellcheck shell=bash` and one "Sourced by sdata/install/setups.sh." line.
- Do 5: below.

## Acceptance 1 — line counts

```
$ wc -l sdata/install/setups.sh sdata/install/setups/*.sh
   40 sdata/install/setups.sh
  101 sdata/install/setups/agent_memory.sh
  142 sdata/install/setups/ai.sh
   29 sdata/install/setups/cli.sh
   82 sdata/install/setups/desktop.sh
   51 sdata/install/setups/globalmenu.sh
    9 sdata/install/setups/_guards.sh
   26 sdata/install/setups/python.sh
   70 sdata/install/setups/session.sh
  204 sdata/install/setups/system.sh
  754 total
```

`setups.sh` 40 ≤ 40. `agent_memory.sh` is 96 before the dry-run fix commit, 101 after. `system.sh` 204 > 200, see Decision 6; all under the 400 cap addendum 3 names.

## Acceptance 2 — function count, recounted from the current file

The job says 21; the current file has 22 including `run_setups`, which stays in `setups.sh`, so the new files must sum to **21** and old-vs-new including `setups.sh` must be empty.

```
$ grep -c '^[a-z_]*()' /tmp/j05-old_setups.sh          # copy of setups.sh at 86c616f5
22
$ grep -c '^[a-z_]*()' sdata/install/setups/*.sh
sdata/install/setups/agent_memory.sh:3
sdata/install/setups/ai.sh:3
sdata/install/setups/cli.sh:1
sdata/install/setups/desktop.sh:3
sdata/install/setups/globalmenu.sh:2
sdata/install/setups/_guards.sh:2
sdata/install/setups/python.sh:1
sdata/install/setups/session.sh:1
sdata/install/setups/system.sh:5
$ cat sdata/install/setups/*.sh | grep -c '^[a-z_]*()'
21
$ diff <(grep -o '^[a-z_]*()' /tmp/j05-old_setups.sh | sort) \
       <(cat sdata/install/setups.sh sdata/install/setups/*.sh | grep -o '^[a-z_]*()' | sort)
(empty)
```

The job's literal form of the diff (new files only) shows exactly one line, `< run_setups()`, which is the function the job says stays behind.

## Acceptance 3 — shellcheck

```
$ shellcheck --version | sed -n 2p
version: 0.11.0
$ shellcheck -x -s bash sdata/install/setups.sh sdata/install/setups/*.sh; echo rc=$?
rc=0
$ shellcheck -x setup install.sh sdata/install/*.sh; echo rc=$?        # CI line 41
rc=0
$ shellcheck -x -s bash sdata/lib/*.sh; echo rc=$?                      # CI line 42
rc=0
$ (cd /tmp && shellcheck -x -s bash "$OLDPWD/sdata/install/setups.sh"); echo rc=$?
rc=0
```

Deliberate-error proof is in Decision 2.

## Acceptance 4 — dry run, baseline vs split

Both runs: `printf '\n' | NO_COLOR=1 ./setup install --dry-run --no-apps` (the newline answers "Continue?"; `NO_COLOR` keeps the diff byte-clean).
Baseline captured on this worktree at `86c616f5` before any edit.

```
$ git rev-parse HEAD
86c616f5c12a6b315440c143479468911ed179ad
$ printf '\n' | NO_COLOR=1 ./setup install --dry-run --no-apps > /tmp/j05-baseline.out 2>&1; echo rc=$?
rc=1
$ wc -l /tmp/j05-baseline.out
82
```

After the split commit (`08ea94ff`), same command:

```
$ printf '\n' | NO_COLOR=1 ./setup install --dry-run --no-apps > /tmp/j05-new.out 2>&1; echo rc=$?
rc=1
$ diff /tmp/j05-baseline.out /tmp/j05-new.out && echo 'DRY-RUN DIFF EMPTY'
DRY-RUN DIFF EMPTY
```

The Setups step as both produce it (identical), from `==> KOOMPI command line` to where the baseline dies:

```
==> KOOMPI command line
     $ mkdir -p /home/userx/.cache/koompi/build/cli
     $ zig build --cache-dir /home/userx/.cache/koompi/build/cli/cache --global-cache-dir /home/userx/.cache/zig --prefix /home/userx/.cache/koompi/build/cli/out -Doptimize=ReleaseSafe
     $ install -Dm755 /home/userx/.cache/koompi/build/cli/out/bin/koompi /home/userx/.local/bin/koompi
  ok koompi CLI installed

==> Global menu daemon (rust)
     $ cargo build --release --locked --target-dir /home/userx/.cache/koompi/build/globalmenu
     $ install -Dm755 /home/userx/.cache/koompi/build/globalmenu/release/global-menu-daemon /home/userx/.local/bin/koompi-global-menu-daemon
  ok koompi-global-menu-daemon installed

==> Shell services daemon
     $ cargo build --release --locked -p koompi-shelld --target-dir /home/userx/.cache/koompi/build/shell-services
     $ install -Dm755 /home/userx/.cache/koompi/build/shell-services/release/koompi-shelld /home/userx/.local/bin/koompi-shelld
  ok koompi-shelld installed

==> Python environment
     $ mkdir -p /home/userx/.local/state/quickshell
  -> venv already exists; syncing requirements only
     $ uv pip install --python /home/userx/.local/state/quickshell/.venv/bin/python -r /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/uv/requirements.txt
  ok venv ready at /home/userx/.local/state/quickshell/.venv

==> Groups, kernel modules and udev
     $ sudo usermod -aG video,input,i2c userx
  -> group changes take effect at your next login
     $ write /etc/modules-load.d/koompi.conf
     $ write /etc/udev/rules.d/99-koompi-uinput.rules
     $ sudo udevadm control --reload-rules

==> Suspend reliability
     $ write /usr/lib/systemd/system-sleep/koompi-btintel-pcie
     $ sudo chmod 755 /usr/lib/systemd/system-sleep/koompi-btintel-pcie

==> Low-RAM defaults (zram, oomd, fast shutdown)
     $ sudo install -Dm644 /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/dist-arch/koompi-sysdefaults/files/tmpfiles.d/koompi-zswap.conf /usr/local/lib/tmpfiles.d/koompi-zswap.conf
     $ sudo install -Dm644 /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/dist-arch/koompi-sysdefaults/files/systemd/user/app.slice.d/10-koompi-oomd.conf /usr/local/lib/systemd/user/app.slice.d/10-koompi-oomd.conf
     $ sudo install -Dm644 /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/dist-arch/koompi-sysdefaults/files/systemd/oomd.conf.d/10-koompi.conf /usr/local/lib/systemd/oomd.conf.d/10-koompi.conf
     $ sudo install -Dm644 /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/dist-arch/koompi-sysdefaults/files/systemd/zram-generator.conf.d/90-koompi.conf /usr/local/lib/systemd/zram-generator.conf.d/90-koompi.conf
     $ sudo install -Dm644 /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/dist-arch/koompi-sysdefaults/files/systemd/system.conf.d/10-koompi-faster-shutdown.conf /usr/local/lib/systemd/system.conf.d/10-koompi-faster-shutdown.conf
     $ sudo install -Dm644 /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/dist-arch/koompi-sysdefaults/files/systemd/system/user@.service.d/10-koompi-faster-shutdown.conf /usr/local/lib/systemd/system/user@.service.d/10-koompi-faster-shutdown.conf
     $ sudo install -Dm644 /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/dist-arch/koompi-sysdefaults/files/systemd/system-preset/80-koompi-sysdefaults.preset /usr/local/lib/systemd/system-preset/80-koompi-sysdefaults.preset
     $ sudo systemctl daemon-reload
     $ sudo systemctl enable systemd-oomd.service
     $ sudo systemctl restart systemd-oomd.service
  ok systemd-oomd running with the KOOMPI thresholds
     $ systemctl --user daemon-reload

==> Local AI
     $ uv tool upgrade litert-lm
  -> /home/userx/.litert-lm/config.json exists; leaving it alone
     $ systemctl --user enable litert-lm.socket
     $ systemctl --user disable litert-lm.service litert-lm-watchdog.service
     $ docker run -d --name searxng --restart unless-stopped -p 127.0.0.1:8888:8080 -v /home/userx/.config/searxng:/etc/searxng -e SEARXNG_BASE_URL=http://127.0.0.1:8888/ docker.io/searxng/searxng:latest

==> Assistant memory
     $ git clone --depth 1 https://github.com/rithythul/koompi-agent-memd.git /home/userx/.cache/koompi/src/koompi-agent-memd
  -> building from /home/userx/.cache/koompi/src/koompi-agent-memd
/home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/lib/common.sh: line 111: cd: /home/userx/.cache/koompi/src/koompi-agent-memd: No such file or directory
  xx cannot enter /home/userx/.cache/koompi/src/koompi-agent-memd
```

### After the dry-run fix (`cbeb877a`)

```
$ printf '\n' | NO_COLOR=1 ./setup install --dry-run --no-apps > /tmp/j05-fixed.out 2>&1; echo rc=$?
rc=0
$ wc -l /tmp/j05-fixed.out
172
$ diff /tmp/j05-baseline.out /tmp/j05-fixed.out | head -3
81,82c81,172
< /home/userx/.herdr/worktrees/koompi-desktop/j05-split-setups-sh/sdata/lib/common.sh: line 111: cd: /home/userx/.cache/koompi/src/koompi-agent-memd: No such file or directory
<   xx cannot enter /home/userx/.cache/koompi/src/koompi-agent-memd
```

Lines 1–80 are identical to the baseline; from line 81 the run now continues.
The rest of the Setups step, then the two entry points `setup` calls directly after the files step:

```
  -> would build in /home/userx/.cache/koompi/src/koompi-agent-memd once it is cloned
     $ install -Dm755 /home/userx/.cache/koompi/build/koompi-agent-memd/release/koompi-agent-memd /home/userx/.local/bin/koompi-agent-memd
  -> would run /home/userx/.local/bin/koompi-agent-memd once to check it answers

==> Desktop portals
     $ systemctl --user daemon-reload

==> Toolkit defaults
     $ gsettings set org.gnome.desktop.interface font-name Google Sans Flex Medium 11 @opsz=11,wght=500
     $ gsettings set org.gnome.desktop.interface color-scheme prefer-dark
     $ gsettings set org.gnome.desktop.interface cursor-theme Adwaita
     $ gsettings set org.gnome.desktop.interface cursor-size 24
  ok cursor fallback already points at Adwaita
     $ fc-cache -f
     $ update-desktop-database /home/userx/.local/share/applications

==> System login session
  ok packaged /usr/bin/koompi-session present
  !! /usr/share/wayland-sessions/koompi.desktop exists and is not KOOMPI-managed; not overwriting it

==> Installing config files
  ... (files step, 60 lines, unchanged by this job)
  ok config files installed

==> Global menu daemon
     $ zig build --cache-dir /home/userx/.cache/koompi/build/global-menu/cache --global-cache-dir /home/userx/.cache/zig -Doptimize=ReleaseSafe
  ok global-menu-daemon built

==> User services
     $ systemctl --user enable --now ydotool
     $ sudo systemctl enable --now bluetooth
     $ systemctl --user enable touch-gestures
     $ systemctl --user enable hypridle
     $ systemctl --user enable koompi-migrate-notify
     $ systemctl --user enable koompi-snapshot-notify

==> Reloading the running session
     $ hyprctl reload
     $ killall -w -q global-menu-daemon
     $ killall -w -q qs
     $ killall -w -q quickshell
  -> would restart the shell

==> Done
```

The `killall` lines are `stop_processes` echoing under `DRY_RUN` (it returns before `pgrep`); nothing was signalled.
The "System login session" warning is this machine's state (a packaged, non-KOOMPI-managed session entry), not a regression: the baseline never reached that step.

## Acceptance 5 — test suite

Baseline at `86c616f5`: 79 passed, 3 skipped, 0 failed (lead addendum 3).

After the split commit alone, before the four test path edits, for the record:

```
77 passed, 3 skipped, 2 failed
failed: test_install_reloads_shell.sh test_sysdefaults.sh
   FAIL: setup_global_menu is gone from setups.sh
   FAIL: setups.sh has no setup_low_ram_defaults
```

(`test_session_list.sh` and `test_cursor_theme.sh` were repointed before that run, having been found by reading first.)

At `08ea94ff`, `6eb210ff` and `cbeb877a`, each:

```
$ NO_COLOR=1 ./tests/run.sh | tail -3
  ok test_zig_build_abort.sh

79 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```

`test_file_length.sh` passes with the `sdata/install/setups.sh` row removed; no new file needs a row.

## Verbatim check

```
$ diff <(sed -n '6,695p' /tmp/j05-old_setups.sh | sort) <(cat sdata/install/setups/*.sh | sort)
62a63
>
99c100
< # a clone into the build cache otherwise. Same shape as setup_shell_services
---
> # a clone into the build cache otherwise. Same shape as setup_shell_services in
119d119
< # below it: build, install to a bin dir, and name what is lost when the toolchain
328c328
< # Installed by KOOMPI. See setup_suspend_hook in sdata/install/setups.sh.
---
> # Installed by KOOMPI. See setup_suspend_hook in sdata/install/setups/system.sh.
553a554,562
> # shellcheck shell=bash            (x9)
559a569,577
> # Sourced by sdata/install/setups.sh. ...   (x9, one per file)
592a611
> # system.sh: build, install to a bin dir, and name what is lost when the toolchain
```

Run before the dry-run fix commit; that commit's four lines are the only code difference since.
