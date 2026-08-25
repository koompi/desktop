# J42 — Hardware quirk layer keyed on DMI, rerunnable (O08)

Serial after J33 (`post_install.sh`, `setups/system.sh`) and J31 (PKGBUILD `_tools`; leave `pkgrel` alone). `.work/OMARCHY-AUDIT.md`
row O08. Omarchy at `~/.tmp/omarchy`: `bin/omarchy-hw-match` (grep `/sys/class/dmi/id/product_name` then `product_family`),
`bin/omarchy-hw-laptop` (lid state file or DMI chassis type 8/9/10/14/30/31/32), `install/hardware/all.sh` (one script per quirk,
vendor first, then generic), `bin/omarchy-apply-hardware` (root, rerunnable after updates). Read first: `installer/src/post_install.sh`
(`main()` at :170-180), `sdata/install/setups/system.sh`, `sdata/dist-arch/koompi-backlight/PKGBUILD` (13: a dependency bundle),
`dots/.local/bin/koompi-lid:20-25` (panel detection via hyprctl — not DMI), `sdata/dist-arch/koompi-shell/PKGBUILD` (`_tools`),
`tests/test_grub_quiet.sh` (sources post_install.sh), `tests/test_packaged_tools.sh`. No DMI read exists in the tree today.

## Files you own
- new `dots/.local/bin/koompi-hw-match`, new `dots/.local/bin/koompi-hw-laptop` (+ `_tools` rows)
- new `sdata/hardware/` tree: `all.sh` + one script per quirk, and new `dots/.local/share/koompi/libexec/apply-hardware`
  (+ its PKGBUILD install lines; `sdata/hardware/**` ships under `/usr/lib/koompi/hardware/`)
- `installer/src/post_install.sh` (one call), `sdata/install/setups/system.sh` (one function), `dots/.local/share/koompi/libexec/update`?
  No — at its row (695): the "rerun after updates" hook goes in `update-lib.sh` as one call after a packaged upgrade (you own that
  one function; J30 merged before you)
- new `tests/test_hardware_quirks.sh`; `.work/J42-report.md`

## Do
1. The two predicates, ported and cited; `koompi-hw-laptop` is the DMI/lid one (`koompi-lid` stays the Hyprland panel one; say
   the difference in each script's header).
2. `apply-hardware`: root, rerunnable, `--dry-run`, logs each quirk's decision to `$XDG_STATE_HOME`-less root path
   `/var/log/koompi/hardware.log`; runs `all.sh`, which runs every quirk script; each quirk script is gated by a predicate and is
   a no-op otherwise. Ship the quirks KOOMPI hardware actually needs: read `sdata/dist-arch/koompi-backlight`, `koompi-hyprland-config`
   and `docs/` for known models (KOOMPI E-series? grep the tree and `README.md`) — if none is cited anywhere, ship the generic ones
   omarchy has that apply to any laptop (`fix-fkeys`, `network` power-save off) and an empty `koompi/` vendor dir with a README, and say so.
3. `post_install.sh` calls it after `ensure_pkgs`; `setups/system.sh` calls it under sudo for the from-git route; `update-lib.sh`
   calls it after a packaged upgrade (sudo prompt is fine: `update_packaged` already uses sudo).
4. `tests/test_hardware_quirks.sh`: fake DMI tree via `KOOMPI_DMI_ROOT` env, shims for whatever the quirks call; proves both
   predicates on three fixtures (laptop by lid, laptop by chassis, desktop), dry-run calling nothing, and every quirk script
   passing `shellcheck -x`.

## Acceptance
1. Paste the test output, `test_packaged_tools.sh`, and the suite tail (baseline +1). `shellcheck -x` on everything: empty.
2. `koompi-hw-match "$(cat /sys/class/dmi/id/product_name)"; echo $?` and `koompi-hw-laptop; echo $?` on this machine, plus
   `apply-hardware --dry-run` as the user (stops at "root required" after listing what it would do).
3. `makepkg -f --nodeps` in `koompi-shell` + `bsdtar -tf` listing `usr/lib/koompi/hardware/all.sh` and the two tools.

## Out of scope
- `koompi-backlight/PKGBUILD`, kernel parameters, GRUB, the ISO.

## Stop conditions
- Never run `apply-hardware` for real here; no sudo.
- If a quirk needs a package not in the Arch repos, list it and skip it.
