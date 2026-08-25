# J36 report — hibernation, the system half (O14)

Branch `j36-hibernation-system-half`, based on `4aca00ec` (main).

## What landed

- New `dots/.local/share/koompi/libexec/hibernation-setup` (254 lines): `setup` (default, root, `--dry-run`) and `status`.
  Preconditions, each refusing with exit 0 and a reason: `/sys/power/image_size` present, root fs btrfs (`findmnt -no FSTYPE -T /`), `btrfs`/`mkinitcpio`/`grub-mkconfig`/`findmnt`/`swaplabel` on PATH plus `/etc/mkinitcpio.conf` and `/etc/default/grub`, `/swap` absent or already a subvolume; `btrfs subvolume create` failing is also a refusal.
  Steps, each checked before acting: `/swap` subvolume + `chattr +C`; `btrfs filesystem mkswapfile -s <MemTotal>k /swap/swapfile` (skipped when `swaplabel` sees a signature); fstab line `/swap/swapfile none swap defaults,pri=0 0 0` with a comment citing `koompi-sysdefaults 90-koompi.conf` (zram pri=100 fills first), fstab backed up to `fstab.koompi-hibernation.bak` and rewritten tmp+mv; `swapon -p 0` unless already in `/proc/swaps` or inside a chroot; `/etc/mkinitcpio.conf.d/koompi-resume.conf` with `HOOKS+=(resume)` then `mkinitcpio -P` (skipped when HOOKS already has `resume`, or has `systemd`, which resumes on its own); `resume=UUID=<fs uuid> resume_offset=<btrfs inspect-internal map-swapfile -r>` merged into `GRUB_CMDLINE_LINUX_DEFAULT` (stale `resume=`/`resume_offset=` words replaced, the rest kept, single line) then `grub-mkconfig -o /boot/grub/grub.cfg`.
  The second run prints "present/already" for every step and calls nothing.
  `status` prints each precondition, the swapfile (size, active), fstab, resume hook, cmdline (and "reboot pending" when `/proc/cmdline` lacks it), and `busctl … CanHibernate`; exits 0 only on `yes`/`challenge`.
- `sdata/dist-arch/koompi-shell/PKGBUILD`: installs it to `/usr/lib/koompi/hibernation-setup` (`pkgrel` untouched).
- `installer/src/post_install.sh`: `setup_hibernation` (path overridable via `KOOMPI_HIBERNATION_SETUP` for the test, as `KOOMPI_UFW_CONF`/`KOOMPI_GRUB_CFG`), failure is a `WARNING:` log line; `main()` calls it after `setup_snapshot_boot`, before `pin_baseline`.
- `sdata/install/setups/system.sh`: `setup_hibernation` under the `systemd_running` guard; `--dry-run` runs the script's own `--dry-run` as the user (no sudo), the real run is `try sudo <script> || warn`.
- `dots/.local/bin/koompi-health`: section "Hibernation", one opt check: `available` on logind yes/challenge, `disabled by policy` on no, else `not set up (run: sudo <script>; '<script> status' says why)`; the path is `~/.local/share/koompi/libexec/…` when present, else `/usr/lib/koompi/…`.
- New `tests/test_hibernation_setup.sh` (220 lines): fake root via `KOOMPI_HIB_ROOT`, shims for btrfs, chattr, mkinitcpio, grub-mkconfig, findmnt, swapon, swaplabel, busctl.

## Decisions and deviations

- **Drop-in, not sed.** `/usr/bin/mkinitcpio:1120-1135` (mkinitcpio 41.1) concatenates `/etc/mkinitcpio.conf` then `conf.d/*.conf` (sorted) into one file and sources it, so `HOOKS+=(resume)` appends after `filesystems` (and after `grub-btrfs-overlayfs`, which `setup_snapshot_boot` sed-appends to the main file). `man 5 mkinitcpio.conf` only says drop-ins "have higher precedence"; the source is the proof. The test sources conf + drop-in as bash and asserts `index(resume) > index(filesystems)`, once.
- **Root check before preconditions in the real run** so a non-root user gets "root required" before anything is probed; `--dry-run` skips it and ends with "root required to apply: sudo …" when not root.
- **Chroot detection** (`/proc/1/root` inode vs `/`): the installer runs this under arch-chroot, where `swapon` would activate the target's swapfile in the live kernel and block the unmount of `/mnt`. Skipped there with a line; fstab activates it at first boot. `mkinitcpio -P` and `grub-mkconfig` run in the chroot as `setup_snapshot_boot`/`setup_grub_btrfs` already do; the installer therefore runs mkinitcpio and grub-mkconfig twice (once here, once in the existing steps). Left as is: the job fixed the order, and folding the regens together means restructuring `setup_snapshot_boot`.
- **UUID fallback.** `findmnt -no UUID -T` needs the udev db; in a chroot without one, `blkid -s UUID -o value <source device>` is asked. Both empty is a non-zero failure, which post_install logs as WARNING and the user reruns.
- **`setups.sh` touched (one line)**, as J33 did: `run_setups` is the only place a setup function is wired.
- **Nested subvolume caveat** (same as omarchy): `/swap` is nested under `@`, so a snapper rollback of `@` leaves an empty `/swap` dir; the fstab swap unit then fails at boot (not fatal) and `resume=` points nowhere (the hook boots normally). Rerunning `sudo /usr/lib/koompi/hibernation-setup` rebuilds it.
- **Comments** on my additions are one-line WHY comments per the comments rule; the existing essays in `post_install.sh`/`system.sh`/`koompi-health` were left alone to keep the diff to the job.
- `shellcheck -x` on the PKGBUILD reports only pre-existing SC2148/SC2034/SC2154 (no shebang, makepkg variables); nothing on the added lines.

## Stop condition 2 — btrfs is not guaranteed

`installer/src/config.zig:45` `btrfs: bool = true` is the default, but `installer/src/ui.zig:233` shows it as a user choice ("fs btrfs/ext4") and `archinstall.zig:135` writes `"fs_type": "ext4"` when it is off.
On an ext4 install the script refuses with exit 0: `not setting up hibernation: root filesystem is ext4; a swapfile with a resume offset needs btrfs`, post_install logs nothing louder than the script's own line, and `koompi doctor` says "not set up".
No ext4 path added (it would need `filefrag`-derived `resume_offset` on a plain swapfile, or a swap partition, which archinstall does not create).

## Acceptance 1 — tests and shellcheck

```
$ NO_COLOR=1 nice -n 19 ionice -c 3 bash tests/test_hibernation_setup.sh
ok test_hibernation_setup.sh
exit=0

$ NO_COLOR=1 nice -n 19 ionice -c 3 ./tests/run.sh   (tail)
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh
==> test_zig_build_abort.sh
  ok test_zig_build_abort.sh

86 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
```
Baseline on `4aca00ec` is 88 tests (85 passed + 3 skipped); this branch runs 89. main has since moved to `37ce475e` and gained `test_notification_exec_hint.sh` and `test_screensaver.sh`, so the lead's post-merge count will be 91.

```
$ shellcheck -x dots/.local/share/koompi/libexec/hibernation-setup tests/test_hibernation_setup.sh \
    installer/src/post_install.sh dots/.local/bin/koompi-health sdata/install/setups/system.sh sdata/install/setups.sh
shellcheck: empty
```

## Acceptance 2 — `--dry-run` on this machine as the user

This machine's root is ext4 (`findmnt -no FSTYPE,SOURCE /` → `ext4 /dev/nvme0n1p2`), so the plan stops at the btrfs precondition, before the root line:

```
$ dots/.local/share/koompi/libexec/hibernation-setup --dry-run
hibernation-setup: kernel supports hibernation (image up to 13GB)
hibernation-setup: would refuse: root filesystem is ext4; a swapfile with a resume offset needs btrfs
exit=0

$ dots/.local/share/koompi/libexec/hibernation-setup status
hibernation status
  ok  kernel supports hibernation (image up to 13GB)
  --  root filesystem is ext4; a swapfile with a resume offset needs btrfs
  --  btrfs is not installed
  ok  /swap is free to create
  --  /swap/swapfile missing
  --  no fstab entry
  --  no resume hook
  --  no resume= on GRUB_CMDLINE_LINUX_DEFAULT
  --  logind CanHibernate: na
exit=1
```
Nothing touched (`git status` clean apart from the job's files; `/etc/fstab`, `/etc/default/grub`, `/etc/mkinitcpio.conf.d` unchanged).
The full plan and the "root required to apply" ending are proved by the test's fake btrfs root (section 3), and the bare non-root run's "root required" exit 1 by section 2.

## Acceptance 3 — package

```
$ cd sdata/dist-arch/koompi-shell && nice -n 19 ionice -c 3 makepkg -f --nodeps
==> Finished making: koompi-shell 1.1-6 (Tue 25 Aug 2026 05:40:16 PM +07)
$ bsdtar -tf koompi-shell-1.1-6-x86_64.pkg.tar.zst | grep -n 'usr/lib/koompi/'
1217:usr/lib/koompi/
1218:usr/lib/koompi/hibernation-setup
1219:usr/lib/koompi/migrate-lib.sh
1220:usr/lib/koompi/update
1221:usr/lib/koompi/update-lib.sh
$ bsdtar -tvf koompi-shell-1.1-6-x86_64.pkg.tar.zst | grep hibernation-setup
-rwxr-xr-x  0 root   root    11941 Aug 25 17:39 usr/lib/koompi/hibernation-setup
```

## Acceptance 4 — line counts (cap 400)

```
  254 dots/.local/share/koompi/libexec/hibernation-setup
  220 tests/test_hibernation_setup.sh
  225 installer/src/post_install.sh
  263 sdata/install/setups/system.sh
   42 sdata/install/setups.sh
  246 dots/.local/bin/koompi-health
  145 sdata/dist-arch/koompi-shell/PKGBUILD
```

## Not verified

The script has never run for real (stop condition): no btrfs machine here, and no sudo. `swapon` in a chroot, `findmnt` UUID in a chroot, and logind flipping to `yes` after a reboot are reasoned from the sources named above, not observed. First real exercise is the next ISO install or `sudo /usr/lib/koompi/hibernation-setup` on a btrfs KOOMPI OS box, then `hibernation-setup status` after the reboot.
