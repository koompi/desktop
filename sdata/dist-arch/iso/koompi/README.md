# KOOMPI OS — archiso profile

A minimal [archiso] profile for building the **KOOMPI OS** live/installer ISO.
It mirrors Arch's official `releng` profile, trimmed to what KOOMPI needs.

**v1 builds a bootable ISO**: DE-agnostic stock Arch + `archinstall`, boots (BIOS +
UEFI) to a networked root shell with the keyring initialized. The KOOMPI-*branded*
path (pacstrap a `koompi-desktop-*` edition from the signed repo, autostart the Zig
installer) is still deferred — see **Status** below.

Base: **Arch Linux only** (x86_64). Release era: **Naga** (v1, see `docs/naming.md`).

## Where this sits in the ISO chain

```
(later) signed [koompi] pacman repo (repo-add + GPG)
        ->  THIS archiso profile (profiledef.sh, packages.x86_64, pacman.conf, airootfs/)
        ->  mkarchiso
        ->  (later) the Zig installer on the live ISO  ->  archinstall  ->  installed KOOMPI
```

The live ISO is **DE-agnostic**. The TARGET edition the user picks at install time
— `koompi-desktop-hyprland` **or** `koompi-desktop-kde` — is pacstrapped onto the
disk by the installer (archinstall engine), **not** listed in `packages.x86_64`.

## Files in this profile

| File | Purpose |
|------|---------|
| `profiledef.sh` | ISO identity, bootmodes (BIOS syslinux + UEFI systemd-boot), file permissions. |
| `pacman.conf` | Build-time repos: standard Arch. `[koompi]` is present but **commented out** for v1. |
| `packages.x86_64` | Live-ISO set: base, kernel, `mkinitcpio-archiso`, `syslinux`, `zsh`, `archinstall`, btrfs/snapper/grub tooling. |
| `syslinux/` | BIOS boot menu (from releng, rebranded; speech + memtest entries trimmed). |
| `efiboot/loader/` | UEFI systemd-boot menu (main entry only). |
| `airootfs/etc/mkinitcpio.conf.d/archiso.conf`, `…/mkinitcpio.d/linux.preset` | archiso runtime initramfs (mounts the live squashfs). |
| `airootfs/etc/systemd/system/getty@tty1.service.d/autologin.conf` | Root autologin on tty1. |
| `airootfs/root/.zlogin` | Fires `~/.automated_script.sh` on login. |
| `airootfs/etc/passwd`, `…/shadow` | Live root (zsh shell, passwordless + autologin). |
| `…/multi-user.target.wants/NetworkManager.service` | Networking in the live session. |
| `…/pacman-init.service` + `etc-pacman.d-gnupg.mount` | Initializes the live pacman keyring so `archinstall` can verify packages. |
| `airootfs/etc/os-release` | The KOOMPI os-release for the live env. |
| `airootfs/root/.automated_script.sh` | Installer autostart **stub** (drops to a shell until the installer ships). |

## Prerequisites

- `archiso` installed on the build host (`pacman -S archiso`).
- Run as **root** (mkarchiso needs it).
- Internet access (pacstraps the live root from the Arch mirrors). **No `[koompi]`
  repo needed for v1** — it is commented out in `pacman.conf`.

## Build

```sh
# from the repo root
sudo mkarchiso -v -w /tmp/koompi-work -o /tmp/koompi-out sdata/dist-arch/iso/koompi/
```

Output: `/tmp/koompi-out/koompi-YYYY.MM.DD-x86_64.iso`. It boots (BIOS + UEFI) to a
root shell with networking and `archinstall` available.

## Status

**Wired (v1 builds + boots + installs via archinstall):** bootloader config dirs
(syslinux + systemd-boot), archiso runtime initramfs, root autologin, live
networking, pacman keyring init, stock-Arch package set.

**Still deferred (KOOMPI-branded ISO):**

1. **Signed `[koompi]` repo.** Commented out in `pacman.conf`. Build the koompi-*
   packages (`repo/build-repo.sh`), GPG-sign + publish, then uncomment `[koompi]`,
   set a real `Server=`, keep `SigLevel = Required`. Never ship `TrustAll`.
2. **Zig installer binary.** `packages.x86_64` has `koompi-installer` commented out;
   it is built from `installer/` and dropped into the airootfs at
   `/usr/local/bin/koompi-installer` (or packaged into `[koompi]`). Until then the
   live session drops to a shell (`.automated_script.sh` is a stub).
3. **Edition pacstrap + repo trust.** Once `[koompi]` is live, the installer
   pacstraps `koompi-desktop-hyprland`/`-kde`; the live env also needs the koompi
   signing key + a `pacman-key` import hook to trust the repo.
4. **Pin archinstall.** Its `user_configuration.json` schema drifts between releases;
   pin a known-good version at the repo/build level.
5. **Branding art.** Boot splash (still releng's `splash.png`), Plymouth / SDDM Naga
   themes are interim placeholders; see `koompi-branding`. Microcode (`amd-ucode` /
   `intel-ucode`) is not yet in the live set.

[archiso]: https://gitlab.archlinux.org/archlinux/archiso
