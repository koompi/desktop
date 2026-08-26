# J46 — Kernel sysctl defaults for the zram machine (J14 finding d)

`.work/J14-report.md:34-35`: the sysdefaults contract named three defaults, so omarchy's
`etc/sysctl.d/99-omarchy-sysctl.conf` (swappiness 150, page-cluster 0, dirty bytes, inotify watches)
was left out and marked "worth its own row if the lead wants it". Rithy wants it (2026-08-26).

The premise that makes those values right is already true here: J14 ships
`sdata/dist-arch/koompi-sysdefaults/files/usr/lib/systemd/zram-generator.conf.d/90-koompi.conf`,
so swap is compressed RAM, not a disk swapfile. Read that file first and confirm it before
you copy a single number — if zram is not actually the swap device on a KOOMPI install,
say so and stop, because half of these values invert.

## Files you own

- new `sdata/dist-arch/koompi-sysdefaults/files/usr/lib/sysctl.d/90-koompi.conf`
- `sdata/dist-arch/koompi-sysdefaults/PKGBUILD` (install line only; **leave `pkgrel` alone**, the lead bumps it at merge)
- `tests/test_sysdefaults.sh` (add assertions; keep the existing ones passing)

Nothing else. `/etc/sysctl.d/` is the admin's; we ship under `/usr/lib/sysctl.d/` so an
admin override in `/etc` still wins.

## Do

1. Read `~/.tmp/omarchy/etc/sysctl.d/99-omarchy-sysctl.conf` and our zram, oomd and
   faster-shutdown drop-ins. For each omarchy key decide take / drop / change, and write the
   reason as a comment above the key in our file. A key you cannot justify for a 4-8 GB KOOMPI
   laptop does not ship. Do not copy omarchy's prose; write ours.
2. Write `90-koompi.conf`. Candidates, each to be argued in the file:
   `vm.swappiness`, `vm.vfs_cache_pressure`, `vm.page-cluster`, `vm.watermark_boost_factor`,
   `vm.watermark_scale_factor`, `vm.dirty_background_bytes`, `vm.dirty_bytes`,
   `vm.dirty_writeback_centisecs`, `fs.inotify.max_user_watches`, `net.ipv4.tcp_mtu_probing`.
3. Add the install line to the PKGBUILD next to the existing `files/` fan-out (the package
   mirrors `files/` onto `/`; follow whatever that loop already does rather than adding a special case).
4. Extend `tests/test_sysdefaults.sh`: build the package, assert the file is in
   `pacman -Qlp` output at the right path, assert every key it sets is a key this kernel
   actually knows (`sysctl -n <key>` reads, never writes), and assert every key carries a comment.
5. `shellcheck` and `shellcheck -x` the test, clean, the way J14 left it.

## Acceptance

Paste real output for each:

1. `cat` the finished `90-koompi.conf` — every key has its reason above it.
2. `bash tests/test_sysdefaults.sh` — all PASS lines, rc 0, including your new assertions.
3. `pacman -Qlp` on the built package, grepped for `sysctl.d`, showing the file.
4. `shellcheck tests/test_sysdefaults.sh && shellcheck -x tests/test_sysdefaults.sh`.
5. The table of decisions: for each of the 10 candidate keys, take/drop and the one-line reason.

## Out of scope

- Applying any of this to the running machine. Never `sysctl -w`, never `sysctl --system`,
  never write into `/etc/sysctl.d/`. This laptop is Rithy's daily driver.
- zram, oomd, shutdown timeouts — J14 shipped them; do not re-tune them.
- `pkgrel`, `pkgver`, dependencies.

## Stop conditions

- Our zram drop-in is absent, disabled, or not the swap device → stop and report.
- The PKGBUILD's file fan-out does not cover a new directory without a code change you would
  have to invent → stop and report what it needs.
- Any step would modify live system state → stop.
