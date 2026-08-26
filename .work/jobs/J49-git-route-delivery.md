# J49 — Prove the git route delivers, in a container, and fix what it misses

Rithy, 2026-08-26: "make sure `koompi update` for any koompi existing users got new update to work
the same as our live system."

Everything from J01-J48 is on `main` and reaches nobody. The packaged route delivers nothing —
`[koompi]` is a skeleton (`sdata/dist-arch/repo/build-repo.sh:19-28`) — so `update_packaged` falls
back to `"$repo/setup" update` (`dots/.local/share/koompi/libexec/update:571-583`). That fallback is
the only path a real user has, and it has never been run end to end on a machine that is not this one.

A read of the two routes says the git route already delivers new tools (`sdata/install/files.sh:322`,
a whole-directory rsync, not a manifest), new QML (`files.sh:31,307-313`) and the sysdefaults files
(`sdata/install/update.sh:152` → `setups.sh:35` → `setups/system.sh:110-116`). Your job is to prove
that by running it, not by reading it, and to close the one gap the read already found.

## The known gap

Nothing in the tree ever runs `sysctl --system`. `setup_low_ram_defaults` copies J46's
`90-koompi.conf` to `/usr/local/lib/sysctl.d/` and then reloads what each *other* file needs —
`systemctl daemon-reload` (`setups/system.sh:133`), `systemctl restart systemd-oomd.service` (`:143`),
`systemctl --user daemon-reload` (`:151`) — none of which re-runs `systemd-sysctl.service`, a
boot-time oneshot. On the packaged route Arch's `25-systemd-sysctl.hook` applies the values at install
time, so a packaged user gets swappiness 150 immediately and a git-route user waits for a reboot.

## Files you own

- `sdata/install/setups/system.sh`
- `tests/test_sysdefaults.sh`
- new `tests/test_update_from_git.sh`
- new `.work/J49-report.md`

**Not yours: `sdata/install/update.sh` and `dots/.local/share/koompi/libexec/update`.** Those belong
to J51. If the container run shows a defect in either, report it with evidence; do not reach across.

## Do

1. Run the real thing in a fresh Arch container (podman, the way J16 did — `podman run --rm -it
   archlinux:latest`, systemd where you can get it, a non-root build user because makepkg refuses
   root). Clone this branch's tree into it, run `./setup` as a first install, then run `koompi update`.
   Record what a user actually ends up with.
2. Be honest about the container's limits: no Wayland session, no user manager in a plain container,
   so the scope you can prove is files, units, tools, package state and exit codes. Say that in the
   report rather than implying the desktop was tested.
3. Compare the result against this tree: does `~/.local/bin` carry every `dots/.local/bin` tool
   (including `koompi-factory-reset`), does the quickshell tree match `dots/.config/quickshell/koompi`,
   did the sysdefaults files land, did `koompi update` exit 0 and take the fallback it should.
4. Fix the sysctl gap in `setup_low_ram_defaults`, after the install loop at `system.sh:116`. Guard it
   the way its neighbours are guarded (`systemd_running`, `run`, dry-run honoured). Applying a
   vendor drop-in is a system-wide action: it re-reads every file in the sysctl.d search path, so say
   in a comment why that is the right call here rather than poking single keys.
5. Add the assertion `tests/test_sysdefaults.sh:131-136` is missing: the function applies sysctl, the
   same way those lines already assert the oomd restart and the user daemon-reload.
6. `tests/test_update_from_git.sh`: the smallest thing that fails if this route stops delivering.
   Shim what has to be shimmed; do not clone from the network in a test.
7. Settle the adjacent question: `setup:236` calls `setup_global_menu` on install, but `run_update`
   (`sdata/install/update.sh:152-157`) does not. Read both and say whether an update leaves the global
   menu stale. It is J51's file, so this is a finding, not a fix.
8. `shellcheck` and `shellcheck -x` clean on everything you touch.

## Acceptance

Paste real output for each:

1. The container transcript's decisive parts: `./setup` finishing, `koompi update` finishing, and the
   route line it printed.
2. `sysctl -n vm.swappiness` inside the container **after the update and without a reboot** — 150.
3. The comparison table: tools, quickshell tree, sysdefaults files — expected vs found.
4. `bash tests/test_sysdefaults.sh` and `bash tests/test_update_from_git.sh`, all PASS, rc 0.
5. `shellcheck` + `shellcheck -x` on each file you touched.
6. The global-menu answer, with the `file:line` that decides it.
7. `bash tests/run.sh` tail.

## Out of scope

- The `[koompi]` pacman repo, signing, `build-repo.sh`, `build-packages.yml`. That is J12 and it stays shut.
- The repo rename (J50) and the release-tag follow (J51). Do not touch their files.
- Changing what `./setup` installs. You are proving and fixing delivery, not redesigning it.

## Stop conditions

- **Nothing you do touches this machine's system state.** No `sysctl -w`, no `sysctl --system`, no
  `./setup`, no `koompi update` outside the container. This laptop is Rithy's daily driver.
- The container cannot run `./setup` at all for a reason that is not our bug (no systemd in the
  container, a missing AUR helper) → say so, get as far as you can, and report what remains unproven.
- A gap you find lives in `sdata/install/update.sh` or `libexec/update` → report it, do not fix it.
