# J14 report — low-RAM defaults: zram, oomd scoped to apps, fast shutdown (O06)

Branch `j14-low-ram-defaults`.
Files touched: `sdata/dist-arch/koompi-sysdefaults/` (new), `sdata/dist-arch/koompi-desktop-hyprland/PKGBUILD` (depends only), `sdata/install/setups.sh` (one new function, one call in `run_setups`), `tests/test_sysdefaults.sh` (new), this file.

## Which package owns the files, and why

New package `koompi-sysdefaults`, not an existing one.

- `koompi-basic` (`sdata/dist-arch/koompi-basic/PKGBUILD`) is a depends-only list with no `package()`; it has never owned a file.
- `koompi-base` is a metapackage with an empty `package()`.
- `koompi-branding` is the only base-tier package that ships `/etc` and `/usr/lib/systemd` files (grub drop-in, sddm conf, the sddm preset), and its header defines it as brand assets.
  Memory and shutdown policy in a package called branding is where the next person fails to look.
- The three defaults are one concern (a small machine keeps its session), they are pure configuration, and every one of them is a vendor drop-in a site can override with a same-named file under `/etc`.
  That is a package of its own, and it is small enough to read in one screen.

`koompi-desktop-hyprland` pulls it in, as the contract says.
It is DE-agnostic, so `koompi-base` would be the natural home for the KDE edition too; that PKGBUILD is not in this job's files and is left for the lead.

## What ships

`files/` mirrors `/usr/lib/`; `package()` installs the tree with one `find` loop, and `setup_low_ram_defaults` installs the same tree under `/usr/local/lib/` for from-git installs (systemd, tmpfiles, presets and zram-generator all read `/usr/local/lib` with the same precedence as `/usr/lib`, verified below; pacman owns nothing there, so a later package install cannot collide on "exists in filesystem").

| /usr/lib path | what | numbers, source |
|---|---|---|
| `systemd/zram-generator.conf.d/90-koompi.conf` | zram0, `zram-size = ram`, `compression-algorithm = zstd`, `swap-priority = 100` | omarchy `default/systemd/zram-generator.conf.d/90-omarchy.conf`. zram-generator's own default is `min(ram / 2, 4096)` (`/usr/share/doc/zram-generator/zram-generator.conf.example`, upstream `man/zram-generator.conf.md` v1.2.1). Omarchy's reason: zstd averages ~3:1 so a full device is ~1/3 of RAM; any smaller cap spills reclaim to disk. No reason found to differ. Priority 100 sits above the 0 a disk swapfile gets. |
| `tmpfiles.d/koompi-zswap.conf` | `w! /sys/module/zswap/parameters/enabled - - - - N` | omarchy `etc/tmpfiles.d/omarchy-zswap.conf`: Arch's kernel enables zswap by default, which in front of swap-on-zram double-compresses and breaks `zramctl` accounting. Part of "zram works", not an extra. |
| `systemd/user/app.slice.d/10-koompi-oomd.conf` | `[Slice] ManagedOOMMemoryPressure=kill`, `ManagedOOMSwap=kill` | omarchy `default/systemd/user/app.slice.d/10-oomd.conf`, verbatim keys. |
| `systemd/oomd.conf.d/10-koompi.conf` | `DefaultMemoryPressureLimit=50%`, `DefaultMemoryPressureDurationSec=20s` | omarchy `etc/systemd/oomd.conf.d/10-omarchy.conf`; systemd's defaults are 60% / 30 s. The app.slice drop-in refers to these thresholds, so they ship together. |
| `systemd/system.conf.d/10-koompi-faster-shutdown.conf` | `[Manager] DefaultTimeoutStopSec=5s` | omarchy `etc/systemd/system.conf.d/10-faster-shutdown.conf`. |
| `systemd/system/user@.service.d/10-koompi-faster-shutdown.conf` | `[Service] TimeoutStopSec=5s` | omarchy `etc/systemd/system/user@.service.d/10-faster-shutdown.conf`; the user manager has its own stop timeout, without this a stuck user service still holds shutdown 90 s. |
| `systemd/system-preset/80-koompi-sysdefaults.preset` | `enable systemd-oomd.service` | same pattern as `koompi-branding`'s `90-koompi.preset` for sddm. `[Install]` of the service has `Also=systemd-oomd.socket`. |

Omarchy's `etc/sysctl.d/99-omarchy-sysctl.conf` (swappiness 150, page-cluster 0, dirty bytes) was left out: the contract names three defaults and sysctl tuning is a fourth.
Worth its own row if the lead wants it; the file and its reasons are in `~/.tmp/omarchy/etc/sysctl.d/`.

`depends=(systemd zram-generator)`. zram-generator 1.2.1-1 is in `[extra]`.

## Finding: on KOOMPI today, oomd has nothing in app.slice to kill

Not the stop condition, but the lead must know before trusting this.

The contract's worry was the drop-in selecting the shell.
It cannot: Hyprland and `qs` are not in the user manager's `app.slice`, they are in the logind session scope under the *system* manager.
Verified on this machine (KOOMPI session, `koompi-session` → `start-hyprland`, no uwsm):

```
$ for p in Hyprland qs; do pid=$(pgrep -o -x $p); printf '%-10s %s\n' $p "$(cut -d: -f3 /proc/$pid/cgroup)"; done
Hyprland   /user.slice/user-1000.slice/session-3.scope
qs         /user.slice/user-1000.slice/session-3.scope

$ systemd-cgls --user | sed -n '/app.slice/,/^│ │ └/p' | head
│   ├─app.slice
│   │ ├─no-mistakes-daemon-eee572d4.service
│   │ ├─dconf.service
│   │ ├─qs-rss-sampler.service
```

The flip side: every app Hyprland execs (browser, terminal, the shell's launcher) is in that same `session-3.scope`, which oomd never looks at.
`app.slice` today holds only user services with no `Slice=` of their own (`dconf`, the KOOMPI ones pin `Slice=session.slice`).
So with this job merged, oomd is enabled, the thresholds are live, the compositor is provably ineligible, and the browser is not yet a candidate either.
Omarchy gets the browser into `app.slice` because `uwsm-app` starts apps as `app-*.scope` units under the user manager.
KOOMPI's equivalent is one change in the launch path (`systemd-run --user --scope --slice=app.slice`, or uwsm), which is outside this job's files.
Recommend a follow-up job; until then O06 is "safe and armed", not "protecting".
The `app.slice.d` file says this in its comment so nobody reads the drop-in and assumes otherwise.

Marking candidacy on `user-1000.slice` or `session-N.scope` instead is not an option: oomd kills a whole child cgroup, and there the child is the entire session.

## Do 5: live checks for the lead (sudo)

This machine has 30 GB and an archinstall-written `/etc/systemd/zram-generator.conf` (`zram-size = 15785`).
zram-generator gives any `*.conf.d` drop-in precedence over the main file, so after the package is installed and the next boot, zram0 becomes 30 GB (`ram`); the existing 15.4 GB device is not resized live, since that would mean `swapoff` on a loaded machine.

```
cd sdata/dist-arch/koompi-sysdefaults && makepkg -f --nodeps && sudo pacman -U --needed koompi-sysdefaults-1.0-1-any.pkg.tar.zst

sudo systemctl daemon-reload                       # generators + system.conf.d
sudo systemctl enable --now systemd-oomd.service
sudo systemctl restart systemd-oomd.service        # thresholds are read at start only
systemctl --user daemon-reload                     # app.slice candidacy is reported by the user manager

zramctl                                            # zstd, 15.4G now; 30G after reboot
systemd-analyze cat-config systemd/zram-generator.conf | grep -v '^#'
cat /sys/module/zswap/parameters/enabled           # N (already N here; tmpfiles applies at boot)

systemctl status systemd-oomd.service --no-pager   # active, "Using ... memory pressure limit 50%..." in the journal
systemd-analyze cat-config systemd/oomd.conf | grep -v '^#'
oomctl                                             # Swap Monitored CGroups / Memory Pressure Monitored CGroups list /user.slice/user-1000.slice/user@1000.service/app.slice
systemctl --user show app.slice -p ManagedOOMMemoryPressure -p ManagedOOMSwap   # kill / kill
systemctl is-enabled systemd-oomd.service          # enabled

systemctl show -p DefaultTimeoutStopUSec           # 5s (if it still says 1min 30s: sudo systemctl daemon-reexec)
systemctl show user@1000.service -p TimeoutStopUSec  # 5s
```

The from-git route (`./setup`) does the same through `setup_low_ram_defaults`, with the files under `/usr/local/lib/`.

## Acceptance 1: built package

```
$ bsdtar -tf koompi-sysdefaults-1.0-1-any.pkg.tar.zst
.BUILDINFO
.MTREE
.PKGINFO
usr/
usr/lib/
usr/lib/systemd/
usr/lib/systemd/oomd.conf.d/
usr/lib/systemd/oomd.conf.d/10-koompi.conf
usr/lib/systemd/system/
usr/lib/systemd/system-preset/
usr/lib/systemd/system-preset/80-koompi-sysdefaults.preset
usr/lib/systemd/system.conf.d/
usr/lib/systemd/system.conf.d/10-koompi-faster-shutdown.conf
usr/lib/systemd/system/user@.service.d/
usr/lib/systemd/system/user@.service.d/10-koompi-faster-shutdown.conf
usr/lib/systemd/user/
usr/lib/systemd/user/app.slice.d/
usr/lib/systemd/user/app.slice.d/10-koompi-oomd.conf
usr/lib/systemd/zram-generator.conf.d/
usr/lib/systemd/zram-generator.conf.d/90-koompi.conf
usr/lib/tmpfiles.d/
usr/lib/tmpfiles.d/koompi-zswap.conf

$ bsdtar -xOf pkg .PKGINFO | grep -E "^(pkgname|pkgver|depend)"
pkgname = koompi-sysdefaults
pkgver = 1.0-1
depend = systemd
depend = zram-generator
```

Built with `BUILDDIR=/tmp/... PKGDEST=/tmp/... makepkg --force --cleanbuild --nodeps`, the same flags as `.github/workflows/build-packages.yml`, which globs `koompi-*/PKGBUILD` and so picks the new package up without a workflow change.

## Acceptance 2: test output and suite tail

```
$ bash tests/test_sysdefaults.sh
built koompi-sysdefaults-1.0-1-any.pkg.tar.zst
ok test_sysdefaults.sh
rc=0
```

The test builds the package into a temp dir, diffs the listing against the seven expected paths (nothing more, nothing less), checks `depend = zram-generator` in the built `.PKGINFO`, runs `systemd-analyze cat-config` on the extracted root for each config drop-in and `systemd-analyze verify` for the two unit drop-ins, greps the verify output for `Unknown key … ignoring` (systemd only warns on a bad key, exit status stays 0), and asserts that `ManagedOOM*=` appears in exactly one file under `sdata/`, `dots/.config/systemd`, `installer/`.
Without makepkg it checks the source tree instead; without systemd-analyze it says so and skips that half, same convention as `test_grub_quiet.sh` with `grub-script-check`.

`./tests/run.sh` tail:

```
$ ./tests/run.sh | tail -6
  ok test_workspace_icon_migration.sh
==> test_workspace_wallpaper_wrap.sh
  ok test_workspace_wallpaper_wrap.sh

57 passed, 0 failed
suite rc=0
```

Other gates from `.work/BACKLOG.md`:

- shellcheck as `.github/workflows/installer.yml:41-45`: clean except two `SC2016` info lines at `sdata/install/setups.sh:164` (the `setup_suspend_hook` heredoc), present on `HEAD` before this branch, not touched.
  `tests/test_sysdefaults.sh` is shellcheck-clean.
- `cli`: `zig build test` exit 0.
- `installer`: `zig build test` exit 2 on this machine, before and after this branch (no file under `installer/` is changed here):
  `build.zig:14:10: error: no field named 'root_source_file' in struct 'Build.ExecutableOptions'`.
  System zig is 0.16.0; `installer/build.zig.zon` says `minimum_zig_version = "0.14.0"`.
  The baseline's "installer 4/4" was taken with a zig that still had that field; this is an environment mismatch for the lead, not a J14 regression.

## Acceptance 3: systemd-analyze

`$ROOT` is the package extracted with `bsdtar -xf`, plus the stock `app.slice` and `user@.service` copied in so `verify` has the units the drop-ins attach to.

```
$ systemd-analyze --root=$ROOT cat-config systemd/system.conf   (comments trimmed)
# $ROOT/usr/lib/systemd/system.conf.d/10-koompi-faster-shutdown.conf
[Manager]
DefaultTimeoutStopSec=5s
rc=0

$ systemd-analyze --root=$ROOT cat-config systemd/oomd.conf   (comments trimmed)
# $ROOT/usr/lib/systemd/oomd.conf.d/10-koompi.conf
[OOM]
DefaultMemoryPressureDurationSec=20s
DefaultMemoryPressureLimit=50%
rc=0

$ systemd-analyze --root=$ROOT cat-config systemd/zram-generator.conf   (comments trimmed)
# $ROOT/usr/lib/systemd/zram-generator.conf.d/90-koompi.conf
# /etc/systemd/zram-generator.conf.d/, or a /dev/null symlink there to turn it off.
[zram0]
zram-size = ram
compression-algorithm = zstd

swap-priority = 100
rc=0

$ systemd-analyze --root=$ROOT cat-config tmpfiles.d   (comments trimmed)
# $ROOT/usr/lib/tmpfiles.d/koompi-zswap.conf
w! /sys/module/zswap/parameters/enabled - - - - N
rc=0

$ systemd-analyze --root=$ROOT cat-config systemd/system/user@.service.d   (comments trimmed)
# $ROOT/usr/lib/systemd/system/user@.service.d/10-koompi-faster-shutdown.conf
[Service]
TimeoutStopSec=5s
rc=0

$ SYSTEMD_UNIT_PATH=$ROOT/usr/lib/systemd/user systemd-analyze --user --man=no verify app.slice
rc=0 (silent = accepted)

$ SYSTEMD_UNIT_PATH=$ROOT/usr/lib/systemd/system systemd-analyze --man=no --recursive-errors=no verify user@1000.service
rc=0 (silent = accepted)

# negative probe: a bad key is only a warning, which is why the test greps the output
$ROOT/usr/lib/systemd/user/app.slice.d/99-bogus.conf:2: Unknown key 'ManagedOOMBogus' in section [Slice], ignoring.
rc=0
```

`/usr/local/lib` (the from-git route) resolves the same way: with the tree copied under `$ROOT/usr/local/lib`, every `cat-config` above found its file (`system.conf`, `oomd.conf`, `zram-generator.conf`, `tmpfiles.d`, `user@.service.d`: one hit each), and `systemd-analyze unit-paths` / `--user unit-paths` list `/usr/local/lib/systemd/system` and `/usr/local/lib/systemd/user`.

## Not done here, for the lead

- `installer/src/post_install.sh` should `systemctl enable systemd-oomd.service` next to `enable_login`'s sddm line; the preset covers `preset-all` only. One line; the installer is outside this job's files.
- `koompi-desktop-kde` does not pull `koompi-sysdefaults`; it should, via `koompi-base`.
- `sdata/install/uninstall.sh` removes only its fixed allowlist, so the `/usr/local/lib` files stay after uninstall, same as the suspend hook it sits next to.
- The launch-path change that puts apps into `app.slice` (see Finding).
- The sysctl row from omarchy, if wanted.

## Round 2: shellcheck on the test

`shellcheck tests/test_sysdefaults.sh` (no `-x`) reported SC2154 at line 63: `depends` referenced but not assigned, since the array exists only after the PKGBUILD is sourced.
Restructured rather than silenced: a `pkgbuild_depends()` helper reads the array in a child `bash -c 'source "$1"; printf ...'`, which also drops the two SC1091 disables the source lines carried.
Commit `5dd99423`.

```
$ shellcheck tests/test_sysdefaults.sh && shellcheck -x tests/test_sysdefaults.sh && echo clean
clean
$ bash tests/test_sysdefaults.sh
built koompi-sysdefaults-1.0-1-any.pkg.tar.zst
ok test_sysdefaults.sh
$ # with koompi-sysdefaults misspelt in the meta's depends, the check still bites:
FAIL: koompi-desktop-hyprland does not depend on koompi-sysdefaults
```
