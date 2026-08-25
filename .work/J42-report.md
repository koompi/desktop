# J42 report — hardware quirk layer keyed on DMI, rerunnable (O08)

Branch `j42-hardware-quirks`.

## What landed

- Predicates `dots/.local/bin/koompi-hw-match` (product_name, then product_family, `grep -qi`; port of omarchy `bin/omarchy-hw-match:5-6`) and `koompi-hw-laptop` (ACPI lid state file, else DMI chassis type 8/9/10/14/30/31/32; port of `bin/omarchy-hw-laptop:4-12`).
  Both headers say how they differ from `koompi-lid` (event handler, hyprctl panel check, needs Hyprland).
  `KOOMPI_DMI_ROOT` and `KOOMPI_LID_DIR` redirect the reads for tests. `koompi-lid` itself is untouched (not in the owned files).
- `sdata/hardware/`: `all.sh` (vendor rows first, then generic; sourced by the runner), `lib.sh` (`hw_not_applied`, `hw_do`, `hw_write` tmp+mv, `hw_file_is`, `hw_kernel_ships`, `hw_systemd_running`), `fix-fkeys.sh`, `wifi-powersave.sh`, `koompi/README.md`.
  Ships as `/usr/lib/koompi/hardware/` in `koompi-shell` (pkgrel untouched per the job).
- `dots/.local/share/koompi/libexec/apply-hardware` → `/usr/lib/koompi/apply-hardware`: root, rerunnable, `--dry-run`; each quirk runs as its own process so one failure cannot stop the rest; every decision is timestamped to stdout and, when applying, to `/var/log/koompi/hardware.log`; exit 1 if any quirk failed.
  Finds its predicates via `$here/../../../bin` (`/bin` when packaged, `dots/.local/bin` from a checkout) and the quirk dir beside itself or at `sdata/hardware`; `KOOMPI_HARDWARE_DIR`, `KOOMPI_HW_LOG`, `KOOMPI_HW_PREFIX` override.
- Hooks: `post_install.sh` `apply_hardware` after `ensure_pkgs` (warns and continues when `koompi-shell` is not in the target); `setups/system.sh` `setup_hardware_quirks` (`try sudo`, runner's own `--dry-run` under `-n`), wired into `run_setups` in `setups.sh` (one line, same precedent as J33); `update-lib.sh` `apply_hardware_quirks` called once in `update_packaged` after "packages up to date" so the git fallback does not run it twice.
- `tests/test_hardware_quirks.sh`.

## Decisions and deviations

- **No KOOMPI model is cited anywhere in the tree.** `grep -rniE 'product_name|dmi|E-series|E11|E13|KOOMPI (E|C|M|Mini)[0-9 ]|laptop model'` over `README.md`, `docs/`, `sdata/`, `installer/`, `dots/.local`, `koompi-backlight`, `koompi-hyprland-config`: nothing but unrelated hits (`kio-admin`, QML model roles).
  So, per the job: the two generic quirks and an empty `koompi/` vendor dir whose README gives the template (`koompi-hw-match '<product>' || hw_not_applied`) and the `cat /sys/class/dmi/id/{sys_vendor,product_name,product_family,chassis_type}` recipe for recording the first model.
- **`wifi-powersave` is ours, not a port.** Omarchy's `install/hardware/network.sh` retires systemd-networkd and disables iwd; it has no power-save quirk (grep `power.?save` over `~/.tmp/omarchy/{install,bin,config,default}`: only `omarchy-powerprofiles-set`).
  The job names "network power-save off" as the generic laptop quirk, so it is implemented as `/etc/NetworkManager/conf.d/koompi-wifi-powersave.conf` with `wifi.powersave = 2`, gated on `koompi-hw-laptop` and `NetworkManager.service` being installed; `nmcli general reload conf` only when a daemon is running (never in the chroot).
- **`fix-fkeys` gates on the kernel shipping `hid_apple`** (`/usr/lib/modules/*/kernel/drivers/hid/hid-apple.ko*` on disk), not on `koompi-hw-laptop`: a Lofree/Keychron plugs into a desktop too, and omarchy applies it everywhere.
  Checked on disk rather than via `modprobe -qn` because in the install chroot `uname -r` is the live ISO's kernel (omarchy's `fix-synaptic-touchpad.sh` comment documents that failure).
  An existing `hid_apple.conf` is left alone (omarchy does the same); our own `koompi-wifi-powersave.conf` is held at its content, since the `koompi-` name marks it ours and an override belongs in a later-sorting file.
- **Decision wording avoids `skip:`/`skipping`**: `tests/run.sh` reads those as "test could not run". Quirks say `not applied: <reason>`.
- **`KOOMPI_HW_PREFIX` drops the root requirement**: with every path redirected under a fake root, `/` is never touched, which is what lets the test prove the real write path unprivileged.
- **`--dry-run` as a user exits 0** and ends on `root required to apply: sudo …`; a real run as a user exits 1 before touching anything.
- **`nmcli`/`systemctl is-active`**: the dry-run test shims every side-effecting command (nmcli, modprobe, tee, install, mv, mkdir, mktemp, cp, chmod) and asserts none is called; `systemctl is-active` is a read query and stays real.
- Comments kept to WHY lines; the citations the job asked for are in the script headers.

## Stop conditions

- `apply-hardware` was never run for real here and no sudo was used; the real-write path was exercised only under `KOOMPI_HW_PREFIX` in the test.
- No quirk needs a package outside the Arch repos (`networkmanager`, `kmod`; nothing installed by the quirks).

## Acceptance 1 — tests

`nice -n 19 ionice -c 3 bash tests/test_hardware_quirks.sh`:

```
hardware quirks: 3 fixtures, dry run clean, 2 quirk scripts idempotent and lint-clean
```

`tests/test_packaged_tools.sh`:

```
packaged tools: 31 shipped, 2 excluded, all accounted for
```

Suite tail, baseline (main, before any change) then after:

```
85 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
exit 0
--
86 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
exit 0
```

`shellcheck -x` on every touched or new script (empty output, exit 0):

```
$ shellcheck -x dots/.local/bin/koompi-hw-match dots/.local/bin/koompi-hw-laptop dots/.local/share/koompi/libexec/apply-hardware sdata/hardware/*.sh tests/test_hardware_quirks.sh installer/src/post_install.sh sdata/install/setups/system.sh sdata/install/setups.sh dots/.local/share/koompi/libexec/update-lib.sh dots/.local/share/koompi/libexec/update
exit 0
```

## Acceptance 2 — this machine (ThinkPad X1 Carbon Gen 13, chassis_type 10, lid present)

```
$ koompi-hw-match "$(cat /sys/class/dmi/id/product_name)"; echo $?
0
$ koompi-hw-laptop; echo $?
0
$ dots/.local/share/koompi/libexec/apply-hardware --dry-run; echo $?
2026-08-25 17:39:41 dry run: nothing will change (quirks from /home/userx/.herdr/worktrees/koompi-desktop/j42-hardware-quirks/sdata/hardware)
2026-08-25 17:39:41 fix-fkeys.sh: would write: /etc/modprobe.d/hid_apple.conf
2026-08-25 17:39:41 wifi-powersave.sh: would write: /etc/NetworkManager/conf.d/koompi-wifi-powersave.conf
2026-08-25 17:39:41 wifi-powersave.sh: would run: nmcli general reload conf
2026-08-25 17:39:41 dry run done; root required to apply: sudo /home/userx/.herdr/worktrees/koompi-desktop/j42-hardware-quirks/dots/.local/share/koompi/libexec/apply-hardware
0
```

## Acceptance 3 — package

`cd sdata/dist-arch/koompi-shell && nice -n 19 ionice -c 3 makepkg -f --nodeps`:

```
==> Finished making: koompi-shell 1.1-6 (Tue 25 Aug 2026 05:37:19 PM +07)
exit 0
$ bsdtar -tf koompi-shell-1.1-6-x86_64.pkg.tar.zst | grep -E "usr/lib/koompi/|usr/bin/koompi-hw"
usr/bin/koompi-hw-laptop
usr/bin/koompi-hw-match
usr/lib/koompi/
usr/lib/koompi/apply-hardware
usr/lib/koompi/hardware/
usr/lib/koompi/hardware/all.sh
usr/lib/koompi/hardware/fix-fkeys.sh
usr/lib/koompi/hardware/koompi/
usr/lib/koompi/hardware/koompi/README.md
usr/lib/koompi/hardware/lib.sh
usr/lib/koompi/hardware/wifi-powersave.sh
usr/lib/koompi/migrate-lib.sh
usr/lib/koompi/update
usr/lib/koompi/update-lib.sh
```
