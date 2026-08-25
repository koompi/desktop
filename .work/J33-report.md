# J33 report — packages: firewall default-deny, LocalSend, fwupd, Khmer OCR

Branch `j33-packages-firewall`.

## What landed

- O25 `koompi-sysdefaults` 1.0-2: depends on `ufw`; ships `/etc/ufw/applications.d/koompi` with `[KOOMPI-KDEConnect]` (1714:1764 tcp+udp) and `[KOOMPI-LocalSend]` (53317 tcp+udp).
  `files/` now mirrors `/` (was `/usr/lib`), so `package()` installs to `$pkgdir/${_file#files/}`; `setup_low_ram_defaults` reads `files/usr/lib`.
  Preset adds `enable ufw.service` and `enable fwupd-refresh.timer`.
- O25 installer: `post_install.sh` `setup_firewall` (rules by profile name, `ENABLED=yes` into `ufw.conf` via `KOOMPI_UFW_CONF`-overridable path, `systemctl enable ufw.service`) and `enable_firmware_refresh`, both before `pin_baseline`.
  No `ufw enable` in the chroot: it would load rules into the live ISO's kernel (omarchy's `firewall.sh` makes the same choice).
- O25 from git: `setup_firewall_defaults` in `setups/system.sh`, called from `run_setups` after `setup_low_ram_defaults`.
  `systemd_running` guard, hands off if `firewalld` is active, installs `ufw` per distro if missing, raw port rules, `ufw allow ssh` only when `sshd` is active, `ufw --force enable`, `systemctl enable ufw.service`.
  Every mutating call goes through `run`, so `--dry-run` prints and does nothing (proved by the shim test).
- O31 `koompi-basic` 1.0-7: `fwupd`. `setup_services` enables `fwupd-refresh.timer` under the same `systemd_running` guard, with a warn when the unit is absent.
- khm `koompi-screencapture` 1.0-4: `tesseract-data-khm`, one comment line pointing at `ScreenshotAction.qml:70`.
- Tests: new `tests/test_firewall_defaults.sh`; `tests/test_sysdefaults.sh` extended for the new layout and preset lines.

## Decisions and deviations

- **Profile location.** ufw reads application profiles from `/etc/ufw/applications.d` only: `config_dir = "/etc"` in `/usr/lib/python3.14/site-packages/ufw/common.py`, and `pacman -Ql ufw` shows no `/usr/lib` or `/usr/share` profile path.
  The package therefore owns an `/etc` file; `kdeconnect 26.08.0-1` does the same (`pacman -Qo /etc/ufw/applications.d/kdeconnect`). No `backup=()` entry, matching kdeconnect.
- **Own profile names** (`KOOMPI-KDEConnect`, not kdeconnect's `KDEConnect`) so the rules do not depend on which package was installed first, and no "Duplicate profile" warning.
- **From-git route uses raw ports, not the profile file.** Writing `/etc/ufw/applications.d/koompi` from `./setup` would make a later `pacman -S koompi-sysdefaults` fail with "exists in filesystem" — the collision `setup_low_ram_defaults` avoids via `/usr/local/lib`, and ufw has no equivalent directory.
  The test holds the from-git ports to the profile's `ports=` lines, so the two routes cannot drift.
- **`ufw allow ssh` when sshd is active.** A from-git `./setup` run over ssh would otherwise cut its own session. Only fires when `systemctl is-active sshd`; the ISO route never adds it. Flagging as a decision the lead may want to revisit.
- **`setups.sh` touched (one line).** Not in "files you own", but `run_setups` is the only place a new setup function is wired; without it the function is dead code.
- **`ufw --force enable` + `systemctl enable ufw.service`** both: on Arch `ufw enable` writes `ENABLED=yes` and loads rules but does not enable the unit.
- **Comments** kept to WHY lines per the comments rule; the citations the job asked for live in the profile file (`userbase.kde.org/KDEConnect`: "KDE Connect uses dynamic ports in the range 1714-1764 for UDP and TCP"; LocalSend README Setup table: incoming 53317 tcp+udp).

## Stop: O17 LocalSend is AUR-only

`pacman -Si localsend` and `pacman -Ss '^localsend'` find nothing (sync dbs from 2026-08-25 08:45).
AUR has `localsend 1.18.2-1`, `localsend-bin`, `localsend-git`, `localsend-go`, plus `localsend-ufw-rules`.
Per the job, no AUR dep added to `koompi-apps`; the PKGBUILD is untouched (no pkgrel bump).
Note for the lead: `koompi-apps` already carries `google-chrome` and `brave-bin`, both AUR ("Both from the AUR" in its own comment), so either that precedent is the rule or those two are the exception; the LocalSend firewall profile ships regardless, so a user who installs LocalSend from AUR or Flatpak is reachable.

## Acceptance 1 — tests

```
$ nice -n 19 ionice -c 3 bash tests/test_firewall_defaults.sh
ok test_firewall_defaults.sh
$ nice -n 19 ionice -c 3 bash tests/test_sysdefaults.sh
built koompi-sysdefaults-1.0-2-any.pkg.tar.zst
ok test_sysdefaults.sh
```

Mutation check (drop `run sudo ufw --force enable` from the setup function):

```
FAIL: never ran 'ufw --force enable'; ran: ufw default deny incoming;ufw default allow outgoing;...;systemctl enable ufw.service;
rc=1
```

`./tests/run.sh` tail (final tree, second full run):

```
  ok test_zig_build_abort.sh

82 passed, 3 skipped, 0 failed
skipped: test_globalmenu.sh test_hypridle_logged.sh test_search_bench_parity.sh
exit=0
```

Baseline 81/3/0 → 82/3/0 (+1, the new test).

Found and fixed on the way: `pkgbuild_depends ... | grep -Fxq` in `test_sysdefaults.sh` is a SIGPIPE race under `pipefail` once the wanted name is not the last element (`grep -q` exits on match, the child bash's `printf` gets SIGPIPE). It bit `tesseract-data-khm` (7th of 8) in the new test. Both tests now capture the list first.

## Acceptance 2 — makepkg, bsdtar, shellcheck

```
koompi-sysdefaults: makepkg ok      -> koompi-sysdefaults-1.0-2-any.pkg.tar.zst
koompi-basic: makepkg ok            -> koompi-basic-1.0-7-any.pkg.tar.zst
koompi-screencapture: makepkg ok    -> koompi-screencapture-1.0-4-any.pkg.tar.zst

$ bsdtar -tf koompi-sysdefaults-1.0-2-any.pkg.tar.zst | grep -v '/$'
.BUILDINFO
.MTREE
.PKGINFO
etc/ufw/applications.d/koompi
usr/lib/systemd/oomd.conf.d/10-koompi.conf
usr/lib/systemd/system-preset/80-koompi-sysdefaults.preset
usr/lib/systemd/system.conf.d/10-koompi-faster-shutdown.conf
usr/lib/systemd/system/user@.service.d/10-koompi-faster-shutdown.conf
usr/lib/systemd/user/app.slice.d/10-koompi-oomd.conf
usr/lib/systemd/zram-generator.conf.d/90-koompi.conf
usr/lib/tmpfiles.d/koompi-zswap.conf

.PKGINFO: depend = systemd / zram-generator / ufw
koompi-basic .PKGINFO: depend = fwupd
koompi-screencapture .PKGINFO: depend = tesseract, tesseract-data-eng, tesseract-data-khm

$ shellcheck -x setup install.sh sdata/install/*.sh sdata/install/setups/*.sh
$ shellcheck -x -s bash sdata/lib/*.sh
$ shellcheck -x installer/src/post_install.sh
(empty)
```

`fwupd-refresh.timer` unit name verified against the Arch `fwupd 2.1.7-1` file list (`archlinux.org/packages/extra/x86_64/fwupd/files/json/`: `usr/lib/systemd/system/fwupd-refresh.timer`); fwupd is not installed on this machine, so the dry-run below shows the warn branch.

## Acceptance 3 — `./setup install --only-setups --dry-run --yes`

```
==> Firewall: deny incoming, allow KDE Connect and LocalSend
     $ sudo ufw default deny incoming
     $ sudo ufw default allow outgoing
     $ sudo ufw allow 1714:1764/tcp comment KDE Connect
     $ sudo ufw allow 1714:1764/udp comment KDE Connect
     $ sudo ufw allow 53317/tcp comment LocalSend
     $ sudo ufw allow 53317/udp comment LocalSend
     $ sudo ufw --force enable
     $ sudo systemctl enable ufw.service
  ok incoming denied, KDE Connect and LocalSend allowed

==> User services
     $ systemctl --user enable --now ydotool
     $ sudo systemctl enable --now bluetooth
  !! fwupd is not installed; firmware updates stay manual
```

## Acceptance 4 — what listens on a KOOMPI laptop today

`ss -tlnp` / `ss -ulnp` on this machine (read-only), non-loopback only:

| Listener | Address | Under the rules |
|---|---|---|
| `kdeconnectd` tcp+udp 1716, udp 5353 (mDNS) | `*` | reachable: 1716 is inside 1714-1764; mDNS to 224.0.0.251:5353 is accepted by ufw's stock `before.rules` (line 68) |
| `kdeconnectd` ~14 ephemeral udp sockets (33551, 39402, …) | `0.0.0.0` | outbound discovery/plugin sockets; replies come in through conntrack, nothing connects to them |
| `chrome` udp 5353 | `224.0.0.251` | mDNS, same stock rule |
| `tailscaled` udp 41641, tcp 54857/64485 | `0.0.0.0` / tailnet IPs | tailscaled's own NAT traversal is outbound-initiated and survives; **inbound over `tailscale0` is blocked** by default deny |
| `wayvnc` tcp 5900 | `100.86.58.128` (tailscale IP) | **blocked** unless `tailscale0` is allowed |
| everything else (ollama 11434, litert-lm 9380, vite 5173, resolver 127.0.2.x:53, …) | loopback | unaffected: ufw never filters `lo` |

The desktop's own services: `koompi-remotedesktop-portal` is a D-Bus backend (`org.freedesktop.impl.portal.RemoteDesktop`), no socket, so the stop condition did not trigger. `koompi-shelld` speaks stdio. Nothing KOOMPI ships listens outside loopback except KDE Connect, which the rules keep.

Findings, not decisions (things a user may rely on that default-deny cuts):

1. **Tailscale / wayvnc.** This machine's existing `/etc/ufw/user.rules` already has `allow in on tailscale0` and the KDE Connect ranges; the KOOMPI rules add nothing that conflicts and remove nothing. A fresh KOOMPI install with Tailscale added later needs `ufw allow in on tailscale0` for tailnet-reachable services (Tailscale's own docs say so). KOOMPI ships neither, so no rule written.
2. **libvirt.** This machine also allows `in on virbr0`; without it VMs lose DHCP/DNS from the host's dnsmasq under default deny. Same status: not shipped, not written.
3. **LAN dev servers** (this machine: 3000-3002 from 192.168.1.0/24) — a developer's own rule, stays as is.
4. **ufw is already active on this machine** (`ENABLED=yes`, `ufw.service` enabled+active), so the from-git step here would only add the two comment-tagged rules alongside the existing ones.

## Out of scope, noted

- ISO profile (`sdata/dist-arch/iso`): no `ufw`/`sysdefaults` reference found; the edition metapackage pulls `koompi-sysdefaults`, which now pulls `ufw`, so the ISO needs no change of its own.
- fwupd EFI binary staging (`fwupdx64.efi` into `/boot/EFI`, omarchy `bin/omarchy-update-firmware:11-13`) belongs to J30's `koompi update` step, not shipped here.
