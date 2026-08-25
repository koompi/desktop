# J36 — Hibernation: the system half (swapfile, resume hook, cmdline), gated (O14)

Serial after J33 (it owns `koompi-sysdefaults/**`, `setups/system.sh`, `post_install.sh` until it merges). `.work/OMARCHY-AUDIT.md`
row O14 — the shell half already exists (`SessionScreen.qml:172-188` Hibernate button gated on `SessionWarnings.canHibernate`,
which asks logind `CanHibernate`, commit `5f77c116`); what is missing is what makes logind say yes. Omarchy at `~/.tmp/omarchy`:
`bin/omarchy-hibernation-setup` (btrfs `/swap` subvolume, `chattr +C`, `btrfs filesystem mkswapfile -s <MemTotal>`, fstab
`pri=0`, `HOOKS+=(resume)`, `resume=`/`resume_offset=` on the kernel cmdline, rerunnable), `bin/omarchy-hibernation-available`.
Read first: `sdata/dist-arch/koompi-sysdefaults/files/**` (zram `swap-priority = 100` at `90-koompi.conf:12-17` already assumes a
`pri=0` disk swapfile), `installer/src/post_install.sh:120-139` (`setup_snapshot_boot`, the only mkinitcpio editing: refuses
`systemd` in HOOKS, appends `grub-btrfs-overlayfs`, `mkinitcpio -P`), `installer/src/post_install.sh:170-180` `main()`,
`sdata/install/setups/system.sh:90-140` `setup_low_ram_defaults`, `tests/test_sysdefaults.sh`, `tests/test_grub_quiet.sh`
(sources post_install.sh), `sdata/dist-arch/koompi-shell/PKGBUILD` (`_tools`, the libexec install lines).

## Files you own
- new `dots/.local/share/koompi/libexec/hibernation-setup` (bash ≤ 400) and its install line in `sdata/dist-arch/koompi-shell/PKGBUILD`
  (leave `pkgrel` alone: the lead bumps it once on merge)
- `installer/src/post_install.sh` (one function + one `main()` line; ≤ 400), `sdata/install/setups/system.sh` (one function)
- `cli/src/main.zig`: no new command — `koompi hibernation setup|status` is out; use `koompi-snapshot`'s shape? No: expose it as
  `koompi update --setup-hibernation`? Also no. Decision: it is a libexec script run by the installer and `./setup`, plus
  `koompi doctor` reports its state — you own one `check` line in `dots/.local/bin/koompi-health` for that.
- new `tests/test_hibernation_setup.sh`; `.work/J36-report.md`

## Do
1. `hibernation-setup`: root-only, rerunnable, `--dry-run`; refuses (exit 0 with a reason) when `/sys/power/image_size` is
   absent, root is not btrfs, or `/swap` cannot be created; creates `/swap` subvolume + `chattr +C` + `btrfs filesystem
   mkswapfile -s <MemTotal>`; fstab entry `pri=0` (zram stays 100, cite the sysdefaults comment); `resume` after `filesystems`
   in HOOKS via a `/etc/mkinitcpio.conf.d/koompi-resume.conf` drop-in if mkinitcpio honours `HOOKS+=` there (verify in
   `man mkinitcpio`; else the same `sed` discipline as `setup_snapshot_boot`), `mkinitcpio -P`; `resume=UUID=… resume_offset=…`
   (`btrfs inspect-internal map-swapfile -r`) into `/etc/default/grub` `GRUB_CMDLINE_LINUX_DEFAULT` idempotently, then
   `grub-mkconfig`. `status` prints each precondition and what `loginctl`/`busctl CanHibernate` says.
2. `post_install.sh`: call it after `setup_snapshot_boot` and before `pin_baseline` (so the baseline has it); failures are
   `|| true` with a line, like the other steps. `setups/system.sh`: the from-git route calls the same script with sudo,
   dry-run aware.
3. `koompi doctor`: one `opt` check "hibernation: available / not set up (run …)".
4. `tests/test_hibernation_setup.sh`: shims `btrfs`, `chattr`, `mkinitcpio`, `grub-mkconfig`, `findmnt`, `swapon`, a fake
   `/sys/power/image_size` via an env override; proves the refusal paths, the idempotent second run (no duplicate fstab/cmdline
   entries), the HOOKS ordering, and dry-run calling nothing.

## Acceptance
1. Paste the test output and the `./tests/run.sh` tail (baseline +1). `shellcheck -x` on every touched script: empty.
2. `hibernation-setup --dry-run` on this machine as the user (not root): paste it — it must show what it would do here and
   stop at the "root required" line without touching anything.
3. `makepkg -f --nodeps` in `koompi-shell` and `bsdtar -tf` showing `usr/lib/koompi/hibernation-setup`.
4. `wc -l` of every touched file under cap.

## Out of scope
- `SessionScreen.qml`, `SessionWarnings.qml`, `Session.qml` (already done), zram config, the ISO.

## Stop conditions
- Never run the script for real (no sudo, no swapfile, no mkinitcpio, no grub on this machine).
- If archinstall's layout on KOOMPI OS has no btrfs root guarantee, say what the installer does for ext4 and report; do not
  add an ext4 path without asking.
