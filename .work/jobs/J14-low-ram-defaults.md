# J14 — low-RAM defaults: zram, oomd scoped to apps, fast shutdown (O06)

`.work/OMARCHY-AUDIT.md` O06. Verified 2026-08-25: no `zram`, `oomd`, or `TimeoutStopSec` anywhere in
`sdata/`, `installer/`, `iso/`. Omarchy's three files at `~/.tmp/omarchy/default/systemd/` (zram-generator
conf, `app.slice.d/10-oomd.conf`, `faster-shutdown.conf`) are the reference; read them and their commit
messages (`git -C ~/.tmp/omarchy log -- default/systemd`) for the reasons.

## Files you own
- new package dir `sdata/dist-arch/koompi-sysdefaults/` (PKGBUILD + files), or the files added to an existing
  base package if one clearly owns system defaults already — read `sdata/dist-arch/koompi-basic/PKGBUILD` and
  `koompi-base*` first and say which and why in the report
- the meta package that pulls it in (`sdata/dist-arch/koompi-desktop-hyprland/PKGBUILD` depends array only)
- `sdata/install/setups.sh` only if the from-git route must also install these (it should: from-git users are
  today's real users); keep the change to one function
- new `tests/test_sysdefaults.sh`; `.work/J14-report.md`

## Do
1. zram: `zram-generator` dependency, config sized to RAM with zstd, matching omarchy's numbers unless you
   can cite a reason to differ.
2. oomd: user `app.slice` drop-in with omarchy's `ManagedOOMMemoryPressure` settings so the compositor and
   shell are never the kill target; enable `systemd-oomd`.
3. Fast shutdown: `DefaultTimeoutStopSec=5s` drop-in.
4. Test: the built package contains the three files at the right paths, and `systemd-analyze verify` (or
   `systemd-analyze cat-config` on a temp root) accepts each drop-in.
5. On this machine (30 GB, so zram is not the point): after the lead installs the package, `zramctl`,
   `systemctl status systemd-oomd`, `oomctl` must show the config live; put the exact commands in the report so
   the lead runs them.

## Acceptance
1. Paste `bsdtar -tf` of the built package.
2. Paste the test output and `./tests/run.sh` tail.
3. Paste the `systemd-analyze` results.
4. Report: which package owns the files and why; the sizing numbers with their source.

## Out of scope
- Swap files, hibernation (O14), anything in the installer TUI.
- Installing on this machine (lead, sudo).

## Stop conditions
- Needing a package not installed for the build; name it.
- Any doubt whether `app.slice` oomd settings can kill the shell: stop and report rather than guess.
