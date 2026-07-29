# KOOMPI OS — Build & Architecture

The canonical build and architecture document for KOOMPI OS. Everything below is
verified against the PKGBUILDs in `sdata/dist-arch/<name>/` and the decisions
locked with the user this session. When this doc and a PKGBUILD disagree, the
PKGBUILD wins and this doc is the bug.

---

## 1. Overview

**Base: Arch Linux, only.** KOOMPI OS is a rolling Arch system with named ISO
eras (snapshot model, not frozen point-releases). This repo
(`koompi-hyprland`) is the end-4/dots-hyprland (illogical-impulse) stack,
rebranded throughout as `koompi-*`.

> **The OS and the desktop are two products out of one tree.** This document
> covers the *OS*: Arch-only, packaged, `/etc/skel`, ISO. The *desktop* on its
> own installs onto Arch, Fedora, Debian and Ubuntu through `./setup` - see
> [`install.md`](install.md). The two paths are mutually exclusive on a given
> machine: `./setup` writes the shell into `$HOME`, the packages write it into
> `/etc/skel` and `/etc/xdg`, and running both leaves two copies competing for
> the same paths. KOOMPI OS uses the package path and never runs `./setup`.

There are **two editions**, both KOOMPI-branded, sharing one house style:

- **KOOMPI Hyprland** — Hyprland compositor + the Quickshell bar/shell.
- **KOOMPI KDE** — a curated lean Plasma desktop.

**House style for BOTH editions:** a top bar/panel, **no dock**, **no global
menu**. The top placement is macOS-*placement*, not a macOS-*menu* — it is a
status panel only.

**Install model: one name per edition, chosen at install time.** A machine
installs exactly one of `koompi-desktop-hyprland` or `koompi-desktop-kde`. The
two are mutually exclusive *by construction* (see §2), so "pick your edition" is
enforced by pacman, not by documentation or installer logic alone. Both editions
ship from a single signed repository.

---

## 2. Package graph

All packages live in `sdata/dist-arch/<name>/PKGBUILD`. "Kind" is one of:

- **meta** — `depends`-only, no `package()` payload.
- **content** — builds and installs real files.
- **alias** — transitional meta that points at another package for back-compat.

### 2.1 Every `koompi-*` package

| Package | Kind | Role |
|---|---|---|
| `koompi-audio` | meta | Audio stack (domain meta). |
| `koompi-backlight` | meta | Brightness/backlight control (domain meta). |
| `koompi-basic` | meta | Baseline CLI tooling (domain meta). |
| `koompi-fonts-themes` | meta | Fonts + base themes (domain meta). |
| `koompi-kde` | meta | KDE apps + system integration — Dolphin, systemsettings, plasma-nm, bluedevil, polkit-kde-agent, NetworkManager, gnome-keyring. **Used by BOTH editions.** |
| `koompi-portal` | meta | XDG desktop portals (domain meta). |
| `koompi-python` | meta | Python/GTK runtime (domain meta). |
| `koompi-screencapture` | meta | Screen capture stack (domain meta). Covers capture for both editions. |
| `koompi-toolkit` | meta | Input toolkit (domain meta). |
| `koompi-widgets` | meta | Hyprland-only widget dependencies. |
| `koompi-hyprland` | meta | Hyprland compositor + tools (depends `hyprland`, `hyprsunset`, `wl-clipboard`). |
| `koompi-quickshell-git` | content | The Quickshell bar/shell + its Qt6/KDE-framework runtime. |
| `koompi-microtex-git` | content | MicroTeX (math rendering) build. |
| `koompi-bibata-modern-classic-bin` | content | Bibata cursor theme (prebuilt). |
| `koompi-base` | **meta (NEW)** | The DE-agnostic foundation shared by every edition. |
| `koompi-branding` | **content (NEW)** | Wallpapers, logo, plymouth/grub/sddm theming, login enablement. |
| `koompi-plasma` | **meta (NEW)** | The curated lean Plasma session (3 packages, NOT plasma-meta). |
| `koompi-kde-config` | **content (NEW)** | `/etc/skel` Plasma layout + shared theming. `conflicts=koompi-hyprland-config`. |
| `koompi-hyprland-config` | content | `dots/.` → `/etc/skel`. NOW also `conflicts=koompi-kde-config`. |
| `koompi-desktop-hyprland` | **meta (NEW)** | The Hyprland *edition* metapackage. |
| `koompi-desktop-kde` | **meta (NEW)** | The Plasma *edition* metapackage. |
| `koompi-desktop` | **alias (NEW)** | Transitional → `koompi-desktop-hyprland` (back-compat). |

### 2.2 `koompi-base` — the shared foundation

`koompi-base` is the DE-agnostic foundation both editions depend on. Its
`depends` (no payload, pure meta):

```
koompi-audio  koompi-backlight  koompi-basic  koompi-fonts-themes
koompi-kde  koompi-portal  koompi-python  koompi-screencapture
koompi-toolkit  koompi-bibata-modern-classic-bin  koompi-branding  sddm
```

Note `koompi-kde` lives in the *base*, not in the KDE edition: it is the KDE
**apps + integration layer** (file manager, network/bluetooth, keyring, polkit)
that the Hyprland session also relies on. It is not a Plasma desktop. `sddm` is
in the base because no `koompi-*` package declared a login manager before and
both editions use it.

### 2.3 Edition metas converging on the base

```
                    ┌──────────────────────────────────────────┐
                    │                koompi-base                │
                    │   (DE-agnostic foundation, meta)          │
                    │                                           │
                    │  audio  backlight  basic  fonts-themes    │
                    │  kde  portal  python  screencapture       │
                    │  toolkit  bibata  branding  sddm          │
                    └──────────────────────────────────────────┘
                          ▲                          ▲
                          │ depends                  │ depends
          ┌───────────────┴─────────┐    ┌───────────┴───────────────────┐
          │ koompi-desktop-hyprland │    │      koompi-desktop-kde        │
          │ (Hyprland edition, meta)│    │   (Plasma edition, meta)       │
          ├─────────────────────────┤    ├────────────────────────────────┤
          │ koompi-base             │    │ koompi-base                    │
          │ koompi-hyprland         │    │ koompi-plasma                  │
          │ koompi-quickshell-git   │    │   ├ plasma-desktop             │
          │ koompi-widgets          │    │   ├ kscreen                    │
          │ koompi-microtex-git     │    │   └ plasma-pa                  │
          │ koompi-hyprland-config ─┼──┐ │ koompi-kde-config ─────────┐   │
          └─────────────────────────┘  │ └────────────────────────────┼───┘
                                       │                              │
                                       │   conflicts= (mutual)        │
                                       └──────────────X───────────────┘
                                          one edition per machine

          koompi-desktop ──depends──▶ koompi-desktop-hyprland   (transitional alias)
```

### 2.4 The `koompi-hyprland-config` ⟷ `koompi-kde-config` conflict

Both `*-config` packages install theming into `/etc/skel/.config`, and they
**collide on 12 shared `/etc/skel/.config` theming paths**. Because two packages
cannot own the same files, each declares the other in `conflicts=`:

- `koompi-hyprland-config`: `conflicts=('koompi-kde-config')`
- `koompi-kde-config`: `conflicts=('koompi-hyprland-config')`

The shared theming seed reused verbatim from `dots/` includes
`kdeglobals`, `Kvantum`, `darklyrc`, `dolphinrc`, `konsolerc`, and the
`kde-material-you-colors` autostart (which overwrites `kdeglobals` from the
wallpaper at login) — the KDE/Qt look that must be identical across both editions
so the desktop feels like one product.

**Why this matters — it is the mechanism, not a side effect:**

1. **It enforces one edition per machine.** pacman *refuses* to install both
   configs together, so a machine physically cannot end up with both editions'
   skel theming. "One edition, chosen at install" is a packaging invariant.
2. **It lets both editions ship from one repo.** Because the collision is
   resolved by `conflicts=` rather than by splitting into separate repositories,
   a single signed `[koompi]` repo can carry *both* editions. The user (or
   installer) selects `koompi-desktop-hyprland` **or** `koompi-desktop-kde`;
   pacman's conflict resolution does the rest.

This is the load-bearing design decision behind the whole edition model.

---

## 3. The curated Plasma edition

`koompi-plasma` is a **deliberately lean** Plasma session. It is **NOT**
`plasma-meta` — that meta drags in the entire bloat list below. The packages
sort into three buckets:

### INSTALL (what `koompi-plasma` actually depends on)

```
plasma-desktop   kscreen   plasma-pa
```

That is the whole list. Three packages.

**Why `plasma-workspace` is not listed:** `plasma-desktop` already pulls
`plasma-workspace` (plasmashell, kwin, krunner, kscreenlocker) **and**
`powerdevil` directly as transitive dependencies. Listing them again would be
redundant noise. The session is complete with just the three names above plus
what they pull.

### AVOID (kept OUT — never install `plasma-meta`)

```
discover            drkonqi               kdeplasma-addons
kinfocenter         plasma-disks          plasma-firewall
plasma-systemmonitor plasma-thunderbolt   plasma-vault
plasma-welcome      print-manager         oxygen
krdp                flatpak-kcm           spectacle
```

`spectacle` is excluded because `koompi-screencapture` already covers capture.
`plasma-browser-integration` is **not** on this list — it stays an **opt-in**
(as it is today), neither force-installed nor blocked.

### AUTHOR (KOOMPI-supplied, layered on top)

- `koompi-kde-config` — the `/etc/skel` Plasma layout (single **top** panel; no
  dock; no bottom taskbar; no global menu) plus the shared KDE/Qt theming copied
  from `dots/`.
- `koompi-branding` — wallpapers, logo, and the sddm/grub/plymouth theming.

The AVOID list keeps the edition lean; the AUTHOR bucket is where the KOOMPI
identity and house style are applied.

---

## 4. Branding & os-release

### `koompi-branding` contents

- Wallpapers → `/usr/share/backgrounds/koompi`
- Logo asset
- Plymouth theme (placeholder for now)
- GRUB theme
- SDDM greeter theme + `/etc/sddm.conf.d/10-koompi.conf` selecting it
  (`Current=koompi`)
- `/usr/lib/systemd/system-preset/90-koompi.preset` that enables
  `sddm.service`

`koompi-branding` `depends=(sddm qt6-declarative qt6-5compat)` and lists
`breeze` as an `optdepends`, the stock theme to fall back to if the KOOMPI
greeter ever fails to render.

### The greeter

`sdata/dist-arch/koompi-branding/files/sddm/theme/` is a real Qt 6 QML greeter,
not a skeleton: a dark card with the clock above it, session selector and power
buttons in the footer, and a shake on a wrong password.

Two things in it are worth not undoing.

**The background has three tiers.** `theme.conf` gives a `backgroundDir`, a
single `background` image and a flat `color`, and `Main.qml` falls through them
in that order. The previous greeter had only the flat colour left once its one
hardcoded wallpaper path stopped existing, and a pure black login screen is what
that looks like from the outside. `backgroundDir` points at
`/usr/share/backgrounds/koompi`, the wallpapers this same package installs, and
one is picked at random per greeter start.

**Nothing is gated on the image loading.** Wallpaper, blur and dim each become
visible on their own, so an unreadable or missing file costs you the photo, not
the login screen.

The lock screen (`modules/koompi/lock/LockSurface.qml`) scans the same directory
with the same blur, which is what makes lock and login read as one system rather
than two themes that happen to ship together.

### Why os-release is NOT a package

`os-release` is **not** shipped by any `koompi-*` package — the `filesystem`
package owns `/etc/os-release`, and two packages cannot own the same path.
Trying to package it would collide with `filesystem`. Instead, the KOOMPI
`os-release` identity is set in **two** places:

1. In the **archiso `airootfs`**, so the live ISO already identifies as KOOMPI.
2. **Written to the target** by the installer's post-install chroot hook, so the
   installed system identifies as KOOMPI too.

This sidesteps the `filesystem` ownership conflict entirely while still
branding both the live and installed environments.

### Login enablement

Login is `sddm`. It is enabled declaratively via the systemd **preset**
(`90-koompi.preset` → `enable sddm.service`) shipped by `koompi-branding`, plus
the `10-koompi.conf` drop-in selecting the greeter theme.

### Naga art — TODO

The greeter is done and no longer interim. What is still TODO is the **Naga**
(v1) *art*: the plymouth theme is a placeholder, and the wallpapers the greeter
draws from are the two brand images plus whatever the wallpaper tarball tier
adds. The target is the per-era visual identity from `docs/naming.md`: a
stylized multi-headed Naga boot splash + wallpaper. This is Phase 6 (see §9).

---

## 5. The ISO chain

The ISO chain is **scaffolded but not yet build-clean** — the skeletons are in
place (repo, archiso profile, installer, CI); signing and wiring remain. The flow:

```
  signed [koompi] pacman repo            archiso profile
  ┌──────────────────────────┐          ┌──────────────────────────────┐
  │ repo-add (build the db)  │          │ profiledef.sh                │
  │ + GPG sign packages & db │ ───────▶ │ packages.x86_64              │
  │                          │          │ pacman.conf (injects [koompi])│
  │ carries BOTH editions    │          │ airootfs (incl. os-release)  │
  └──────────────────────────┘          └──────────────────────────────┘
                                                       │
                                                       ▼
                                                  mkarchiso
                                                       │
                                                       ▼
                                        ┌──────────────────────────────┐
                                        │ live ISO + Zig installer      │
                                        └──────────────────────────────┘
```

1. **Signed `[koompi]` pacman repo** — `repo-add` builds the repo database; the
   packages and the database are GPG-signed. This repo carries **both** editions
   (the §2.4 conflict is what makes that safe).
2. **archiso profile** — `profiledef.sh`, `packages.x86_64`, a `pacman.conf`
   that injects the `[koompi]` repo, and the `airootfs` overlay (which sets the
   KOOMPI `os-release`).
3. **`mkarchiso`** — builds the live ISO from the profile.
4. The **KOOMPI installer** (Zig/libvaxis) rides on the live ISO (see §6).

### Scaffolded locations

| Path | Holds |
|---|---|
| `sdata/dist-arch/repo/` | The signed `[koompi]` repo (repo-add + GPG). |
| `sdata/dist-arch/iso/koompi/` | The archiso profile (profiledef.sh, packages.x86_64, pacman.conf, airootfs). |
| `installer/` | The Zig (libvaxis) TUI installer. |
| `.github/workflows/` | CI: build/sign the repo, build the ISO. |

---

## 6. Installer architecture

**Face = Zig (libvaxis TUI). Engine = `archinstall`.** The split is deliberate:
`archinstall` owns the **dangerous 20%** — partitioning, LUKS, `pacstrap`,
bootloader install, btrfs setup. The Zig binary is a **thin orchestrator**, not a
reimplementation of any of that.

### Data flow

```
  Zig libvaxis TUI  ──collect answers (edition, disk, user, locale, …)
        │ emit
        ▼
  user_configuration.json + user_credentials.json + KOOMPI archinstall profile
        │ exec
        ▼
  archinstall --silent    ← the dangerous 20%, done by the ENGINE:
      • partition / LUKS / pacstrap / bootloader (GRUB)
      • btrfs subvolume layout (@, @home, @var_log, …)
      • install the koompi-desktop-<edition> metapackage  (packages field)
        │ then
        ▼
  post-install chroot hook    ← the KOOMPI-specific last 5%, by the FACE:
      • snapper config over archinstall's existing subvolumes
      • snap-pac (snapshot per pacman txn) + grub-btrfs (boot menu)
      • pin the read-only @baseline snapshot  (= factory-reset point)
      • enable sddm.service
      • write /etc/os-release
```

1. The TUI **collects answers**.
2. It **emits** `user_configuration.json` + `user_credentials.json` and **selects
   the KOOMPI `archinstall` profile**.
3. It **execs `archinstall --silent`** — the **engine** does the dangerous work
   unattended: partitioning, LUKS, `pacstrap`, the **GRUB** bootloader, the
   **btrfs subvolume layout**, and **installing the chosen
   `koompi-desktop-<edition>` metapackage** (via archinstall's `packages` field).
4. A **post-install chroot hook** finishes the KOOMPI-specific **last 5%**:
   `snapper` config over archinstall's subvolumes, `snap-pac` + `grub-btrfs`,
   pinning the read-only **`@baseline`** snapshot (see §7), enabling `sddm`, and
   writing `os-release`. It does **not** create subvolumes or install the
   edition — those are archinstall's job.

### Risk: archinstall schema drift — and why we must NOT hand-write the JSON

`archinstall`'s JSON config schema **drifts between releases**, and an adversarial
audit (verified against `archinstall` source) proved the scaffold's hand-written
JSON would make a `--silent` install **silently produce a broken system**:

| key | wrong (hand-written) | what archinstall actually reads | effect |
|-----|----------------------|----------------------------------|--------|
| disk layout | flat `disk_config: {device, filesystem, encrypt, btrfs_subvolumes}` | `disk_config.device_modifications[].partitions[]` with per-partition `obj_id` UUIDs, `size`/`start` objects, btrfs subvols **nested** under the partition's `btrfs` key | unknown keys ignored → **no disk setup at all** |
| user password | `"password"` | `"!password"` (plaintext) or `"enc_password"` (hash) | user **silently skipped → no login** |
| root password | `"root_password"` plaintext | only `"root_enc_password"` (a **hash**) | **passwordless root** |
| bootloader | top-level `"bootloader"` | `"bootloader_config": {"bootloader": "Grub"}` | dropped → defaults to systemd-boot → **breaks grub-btrfs** |
| encryption | `encrypt` bool inside `disk_config` | a **separate** top-level `disk_encryption` block | LUKS ignored |

The decisive lesson: `disk_config` needs per-partition `obj_id` UUIDs that **only
`archinstall` can mint** — they cannot be hand-fabricated. **Mitigation (two
parts):** (1) **PIN an exact `archinstall` version** on the ISO; (2) **GENERATE**
`user_configuration.json` / `user_credentials.json` from that pinned
`archinstall`'s own `--dry-run`/save-config flow and parameterize the result —
never hand-write them. The literals in `installer/src/archinstall.zig` are
**shape templates that document the verified schema**, not a runnable config.

### Targets

First targets are the **KOOMPI laptop + mini-desktop**. Known hardware shrinks
the partitioning edge-case surface, which is exactly where the installer risk
concentrates.

---

## 7. Semi-immutable design

KOOMPI OS is **semi-immutable / resettable — NOT truly immutable.** pacman stays.
The goal is "factory reset to original installed state" and "reset my desktop",
not a locked rootfs.

### btrfs subvolume layout

Subvolumes `@`, `@home`, `@var_log`, … — the standard snapshot-friendly layout.
Bootloader is **GRUB** specifically so `grub-btrfs` can offer a bootable snapshot
menu.

### Snapshots

- **snapper** — manages btrfs snapshots.
- **snap-pac** — takes an automatic pre/post snapshot **per pacman transaction**,
  so every package change is individually revertable.
- **grub-btrfs** — adds a **bootable snapshot menu** to GRUB; you can boot
  straight into any snapshot.

### Two kinds of reset

- **Factory reset → the pinned `@baseline` snapshot.** At first boot, a
  **read-only `@baseline`** snapshot is pinned, capturing the original installed
  state. Restoring it returns the whole system to factory.
- **Desktop reset → reseed from `/etc/skel`.** Re-seeding `~/.config` from
  `/etc/skel` (the edition's `*-config` payload) resets the *desktop* without
  touching the rest of the system.

---

## 8. Local dev vs ISO

The two paths carry **different closures**:

- **Local dev (`install-deps.sh` in `sdata/dist-arch/`)** builds **only the
  Hyprland edition closure**. It cannot build both editions at once on one
  machine, because `koompi-kde-config` `conflicts` `koompi-hyprland-config` — the
  same §2.4 mechanism that enforces one edition per machine also constrains the
  local dev box to one edition.
- **The signed repo + ISO** carry **both editions**. The conflict is fine there
  because the repo only *stores* both; pacman only ever *installs* one at a time
  on any given target.

Mental model: locally you are *running* the Hyprland edition; the repo/ISO is the
*distribution* of both.

---

## 9. Roadmap (phased)

| Phase | Scope | Status |
|---|---|---|
| **1** | **Packages** — koompi-base, koompi-branding, koompi-plasma, koompi-kde-config, edition metas, the `conflicts=` wiring. | **DONE** (build-verified this session) |
| **2** | **Signed repo + CI** — `sdata/dist-arch/repo/` (repo-add + GPG), `.github/workflows/` to build & sign. | TODO |
| **3** | **archiso** — `sdata/dist-arch/iso/koompi/` profile (profiledef.sh, packages.x86_64, pacman.conf injecting `[koompi]`, airootfs + os-release), `mkarchiso`. | TODO |
| **4** | **Zig installer** — `installer/` libvaxis TUI → archinstall JSON → `--silent` → post-install chroot hook. Pin archinstall version. | TODO |
| **5** | **Immutability wiring** — btrfs subvols, snapper, snap-pac, grub-btrfs, pinned `@baseline`, `/etc/skel` reseed. | TODO |
| **6** | **Branded art** — Naga (v1) plymouth boot splash and wallpapers. The sddm greeter itself is **DONE** (Qt 6 QML theme, `Current=koompi`); what remains is the art it and plymouth display. | TODO |
| **LAST** | **AI integration** — intentionally the final phase (assistant currently unnamed; candidate name *Mealea*). | TODO |

---

## Appendix — component names (the "world")

From `docs/naming.md`. Release era = **Naga** (v1).

| Component | Name |
|---|---|
| Desktop shell | **Bayon** |
| Installer | **koompi-installer** (plain — no codename) |
| Software store | **Psar** |
| Welcome app | **Suostei** |
| Settings / control | **Reach** |
