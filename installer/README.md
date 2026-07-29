# The KOOMPI OS installer

> **⚠️ THIS IS A SCAFFOLD. ⚠️**
> Nothing here is tested. **No real disk operations are wired up.** Every
> dangerous step (partitioning, LUKS, pacstrap, bootloader) is delegated to
> `archinstall` and is currently a **TODO / REVIEW** stub. Do **not** run this
> against a machine you care about. It compiles toward a TUI skeleton, not a
> working installer.

The **KOOMPI installer** sets up **KOOMPI OS — Naga** on your machine.
It is a deliberately *thin* program: a **Zig + [libvaxis](https://github.com/rockorager/libvaxis)
TUI face** over the **`archinstall` engine**.

> **Design spec:** [`docs/ui-ux.md`](docs/ui-ux.md) — the authoritative 10-screen
> flow, the visual/theme system, and the face/engine/spec seams that make the
> installer rebrandable. The shipped theme is [`themes/koompi.toml`](themes/koompi.toml).

## The split: face vs. engine

It does **not** reimplement partitioning, encryption, `pacstrap`, or
bootloader installation. That is the dangerous ~20% of an installer, and
`archinstall` already owns it (and is maintained by Arch). The installer's only jobs:

```
  ┌─────────────────────────────────────────────────────────────────────┐
  │ KOOMPI installer (Zig + libvaxis)   "the FACE"                      │
  │   collect answers via a TUI state machine                           │
  │   → InstallConfig (src/config.zig)                                   │
  │   → emit archinstall user_configuration.json + user_credentials.json│
  │   → pick the KOOMPI edition package                                  │
  └───────────────┬─────────────────────────────────────────────────────┘
                  │ exec
                  ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │ archinstall (pinned)              "the ENGINE"                       │
  │   partition · LUKS · btrfs subvolumes · pacstrap · GRUB             │
  └───────────────┬─────────────────────────────────────────────────────┘
                  │ chroot
                  ▼
  ┌─────────────────────────────────────────────────────────────────────┐
  │ post_install.sh                   "the FINISH"                      │
  │   snapper @baseline · snap-pac · grub-btrfs · enable sddm · os-release│
  └─────────────────────────────────────────────────────────────────────┘
```

## Data flow

1. **Collect** — the TUI (`src/main.zig`) walks a state machine:
   `Welcome → Locale/Timezone/Keyboard → Disk → User/Hostname → Edition →
   Encrypt → Review → Run`. Answers accumulate into an `InstallConfig`
   (`src/config.zig`).
2. **Serialize** — `src/archinstall.zig` turns the `InstallConfig` into the two
   files `archinstall` reads:
   - `user_configuration.json` — disk layout (btrfs `@`, `@home`, … subvolumes),
     `bootloader = "Grub"`, locale/keyboard, and the **target package**
     (`koompi-desktop-hyprland` **or** `koompi-desktop-kde`, chosen by edition).
   - `user_credentials.json` — the primary user's password (root is left LOCKED;
     admin is via the sudo user). **Secret.** Written to tmpfs, `chmod 600`,
     deleted right after `archinstall` exits, never logged.
3. **Run** — `archinstall --config … --creds … --silent` does the install.
4. **Finish** — a post-install **chroot hook** (`src/post_install.sh`) pins the
   read-only `@baseline` snapshot, installs `snap-pac` + `grub-btrfs`, enables
   `sddm.service`, and writes `/etc/os-release` to the target.

## ⚠️ The schema-pinning risk

`archinstall`'s `user_configuration.json` / `user_credentials.json` schema
**drifts between releases**. If the ISO ships a different `archinstall` than the
one this code was written against, the JSON we emit may be silently rejected or
misinterpreted.

**Mitigation:** the version is a single named constant — `ARCHINSTALL_VERSION`
in `src/archinstall.zig` — and the **archiso profile must pin exactly that
version**. Bump the constant and the JSON serializer together, never one alone.

## Editions

Chosen at install time, both KOOMPI-branded, both top-bar / no-dock / no-global-menu:

| Edition          | Target metapackage         |
|------------------|----------------------------|
| KOOMPI Hyprland  | `koompi-desktop-hyprland`  |
| KOOMPI KDE       | `koompi-desktop-kde`       |

The two `*-config` packages `conflicts=` each other on `/etc/skel` theming
paths, so pacman enforces **one edition per machine** — exactly what "choose at
install" needs.

## Layout (semi-immutable / resettable)

btrfs subvolumes (`@`, `@home`, `@var_log`, …) + `snapper` + `snap-pac`
(auto pre/post snapshot per pacman txn) + `grub-btrfs` (bootable snapshot menu)
+ a pinned **read-only `@baseline` snapshot** taken at first boot = "factory
reset to original installed state". GRUB is the bootloader specifically so
`grub-btrfs` can offer snapshots at boot.

## Build / run

Target toolchain: **Zig 0.14.x**.

```sh
# Fetch deps (fills the placeholder hash in build.zig.zon) and build:
zig build

# Run the (skeleton) TUI:
zig build run
# or:
./zig-out/bin/koompi-installer
```

> The `.hash` in `build.zig.zon` is a **placeholder**. The first `zig build`
> will fail and print the real hash to paste in — see the comment there.
> The libvaxis revision is also pinned in `build.zig.zon`; pick a tag/commit
> that supports your Zig **0.14.x** toolchain (libvaxis `main` tracks newer Zig).

## Files

| File                  | Role                                                        |
|-----------------------|-------------------------------------------------------------|
| `build.zig`           | declares the `koompi-installer` exe + the libvaxis dependency wiring   |
| `build.zig.zon`       | package manifest + pinned libvaxis dep (placeholder hash)   |
| `src/main.zig`        | TUI state machine (the face) — **draw loop is a stub**      |
| `src/config.zig`      | `InstallConfig` — the accumulated answers                   |
| `src/archinstall.zig` | serialize JSON · exec archinstall · run the chroot hook     |
| `src/post_install.sh` | the actual post-install chroot script (embedded via Zig)    |
