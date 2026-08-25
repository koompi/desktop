# J33 — Packages: firewall default-deny, LocalSend, fwupd, Khmer OCR (O25 O17 O31-dep, AUDIT khm row)

`.work/OMARCHY-AUDIT.md` rows O25, O17, the package half of O31, and the ALREADY BUILT note "add `tesseract-data-khm`".
Omarchy at `~/.tmp/omarchy`: `install/config/firewall.sh:2-7`, `bin/omarchy-menu-share:17-45`, `bin/omarchy-update-firmware:6-13`.
Read first: `sdata/dist-arch/koompi-sysdefaults/PKGBUILD` + `files/` (J14's pattern: vendor drop-ins, enabling left to
preset/installer/setup), `sdata/install/setups/system.sh` `setup_low_ram_defaults` and `setup_services`,
`installer/src/post_install.sh` (`enable_login`, the oomd enable if J14 Do 5 added one), `sdata/dist-arch/koompi-apps/PKGBUILD`
(`kdeconnect` at line 100), `sdata/dist-arch/koompi-basic/PKGBUILD`, `sdata/dist-arch/koompi-screencapture/PKGBUILD`,
`tests/test_sysdefaults.sh`, `README.md:132` (KDE Connect is the phone story).

## Files you own
- `sdata/dist-arch/koompi-sysdefaults/PKGBUILD` and `files/**` (pkgrel bump)
- `sdata/dist-arch/koompi-apps/PKGBUILD`, `sdata/dist-arch/koompi-basic/PKGBUILD`, `sdata/dist-arch/koompi-screencapture/PKGBUILD` (pkgrel bumps)
- `sdata/install/setups/system.sh`, `installer/src/post_install.sh`
- `tests/test_sysdefaults.sh` (extend), new `tests/test_firewall_defaults.sh` if separate reads better; `.work/J33-report.md`

## Do
1. (O25) Ingress default-deny with `ufw`: `koompi-sysdefaults` depends on `ufw` and ships an application profile set
   under `/usr/lib/…` only if ufw reads one from there — verify with `pacman -Ql ufw` and the ufw docs; otherwise ship
   `/etc/ufw/applications.d/koompi` (a package may own `/etc` files; say which you chose and why). Rules: deny incoming,
   allow outgoing, allow KDE Connect (1714-1764 tcp+udp — cite the kdeconnect docs), allow LocalSend (53317 tcp+udp).
   Enabling (`ufw --force enable`, `systemctl enable ufw`) goes where J14 put oomd's: `post_install.sh` for the installer and
   `setup_low_ram_defaults`-style function for `./setup` (sudo, guarded by `systemd_running`, idempotent, dry-run aware).
   Also open the ports for the from-git route, since `./setup` machines have no package.
2. (O17) `localsend` in `koompi-apps` `depends` (check the exact Arch package name with `pacman -Si`; if it is AUR-only,
   stop and report — no AUR deps in a metapackage). It ships its own `.desktop`, so Search finds it; nothing else to wire.
3. (O31) `fwupd` in `koompi-basic` `depends` (J30 makes `koompi update` use it; you only ship it). Enable `fwupd-refresh.timer`
   beside the ufw enable, same guards.
4. (khm) `tesseract-data-khm` beside `tesseract-data-eng` in `koompi-screencapture`; one comment line saying OCR already
   uses every installed language (`modules/common/utils/ScreenshotAction.qml:70`).
5. Tests: `test_sysdefaults.sh` (or the new file) sources the PKGBUILDs the way it already does and proves each dependency
   row and the ufw profile file exist; shims `ufw`/`systemctl` and proves the setup function's calls and its dry-run
   prints without calling.

## Acceptance
1. Paste the test output and the `./tests/run.sh` tail (baseline 81/3/0, +0 or +1).
2. `makepkg -f --nodeps` in each touched package dir (`koompi-sysdefaults` builds a payload; the metapackages just need to
   parse) and `bsdtar -tf` of the sysdefaults package showing the profile file. `shellcheck -x` on setups + post_install
   (CI's exact lines in `.github/workflows/installer.yml`): empty.
3. `./setup --dry-run` (or the flag the tree uses; `sdata/install/setups.sh` says) showing the firewall step's would-do lines.
4. A paragraph in the report: which inbound services a KOOMPI laptop runs today (`ss -tlnp` on this machine, read-only)
   and which of them the rules keep reachable. Anything you would block that a user relies on is a finding, not a decision.

## Out of scope
- `libexec/update` and `koompi-health` (J30), any shell QML, the ISO profile (`sdata/dist-arch/iso`, report if it needs
  the package), `koompi-base`.

## Stop conditions
- Never run `ufw enable`, `systemctl enable`, `pacman -S`, or any sudo on this machine; makepkg, shims and dry-run only.
- If ufw would block something the desktop needs (the remote-desktop portal, `koompi-remotedesktop-portal`, listens?),
  stop and report the port before writing the rule.
