#!/usr/bin/env bash
# post_install.sh — KOOMPI OS post-install chroot hook.
#
# ⚠️ SCAFFOLD — UNTESTED. Runs INSIDE the freshly pacstrapped target via
#    `arch-chroot /mnt`. Every btrfs / snapper / bootloader line is a REVIEW
#    point. Do NOT run on a live system.
#
# Responsibilities (the ~last 5% archinstall doesn't do for us):
#   1. snapper config for `/`, wired to archinstall's existing @ / @snapshots
#   2. the un-prunable @baseline snapshot = "factory reset to original install"
#   3. snap-pac  (auto pre/post snapshot per pacman transaction)
#   4. grub-btrfs (bootable snapshot submenu in GRUB) + the grub-btrfs-overlayfs
#      initramfs hook so a booted snapshot is a usable read-write system
#   5. enable sddm.service (belt-and-suspenders: koompi-branding ships a preset
#      that already enables it — harmless to enable again)
#   6. write /etc/os-release (NOT shipped by any package — filesystem owns the
#      stock one; we overwrite with KOOMPI identity)
#
# FACTORY RESET (user-facing): roll back to @baseline with
#   `sudo snapper -c root rollback <N>` (N = the @baseline number from
#   `snapper -c root list`) then reboot — or pick @baseline from the grub-btrfs
#   boot menu. (The desktop-only reset is the /etc/skel reseed, handled elsewhere.)
#
# Idempotent: safe to re-run. Each step checks before it acts.

set -euo pipefail

log() { printf '[koompi-installer] %s\n' "$*"; }

# ─────────────────────────────────────────────────────────────────────────────
# 0. Packages the post-install needs. archinstall pacstrapped the edition
#    metapackage already; these are the snapshot-tooling extras.
#    REVIEW: pin versions on the ISO if reproducibility matters.
# ─────────────────────────────────────────────────────────────────────────────
ensure_pkgs() {
  local want=(snapper snap-pac grub-btrfs inotify-tools)
  local missing=()
  for p in "${want[@]}"; do
    pacman -Qq "$p" &>/dev/null || missing+=("$p")
  done
  if ((${#missing[@]})); then
    log "installing: ${missing[*]}"
    # TODO/REVIEW: live ISO must have the [koompi] + base repos reachable here.
    pacman -S --noconfirm --needed "${missing[@]}"
  else
    log "snapshot tooling already present"
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 1. snapper config for root. archinstall's btrfs layout already created the @
#    subvolume mounted at / and a .snapshots subvol — so we must NOT let
#    `snapper create-config` make its own (it would try to create
#    /.snapshots and fail / conflict). Create the config file, then point it at
#    the existing layout.
#    REVIEW: this is the fiddliest interaction with archinstall's layout.
# ─────────────────────────────────────────────────────────────────────────────
setup_snapper() {
  if snapper list-configs 2>/dev/null | grep -qw root; then
    log "snapper 'root' config already exists"
    return
  fi
  log "creating snapper 'root' config"
  # If archinstall already made /.snapshots, create-config refuses. Handle both.
  if mountpoint -q /.snapshots; then
    umount /.snapshots || true
  fi
  if [ -d /.snapshots ]; then
    rmdir /.snapshots 2>/dev/null || true
  fi
  snapper -c root create-config /
  # archinstall+snapper coexistence — the full 5-step dance. `create-config`
  # just made its OWN .snapshots subvolume nested inside @ (i.e. @/.snapshots).
  # We must delete it and restore archinstall's REAL @snapshots subvol at
  # /.snapshots. Otherwise every snapshot we create (including @baseline) lands
  # in the nested subvol and is HIDDEN the moment fstab remounts @snapshots over
  # it on the next boot — silently losing the factory-reset point.
  btrfs subvolume delete /.snapshots 2>/dev/null || true
  mkdir -p /.snapshots
  mount /.snapshots 2>/dev/null || mount -a || true
  if ! btrfs subvolume show /.snapshots >/dev/null 2>&1; then
    log "WARNING: /.snapshots is not archinstall's @snapshots subvol — the"
    log "         @baseline snapshot may not persist across reboot."
  fi
  # enable-only (no --now: a chroot can't START units; the timer is enabled at
  # boot). snapper-cleanup auto-prunes, but @baseline is created with NO cleanup
  # algorithm (see pin_baseline) so it is exempt.
  systemctl enable snapper-timeline.timer snapper-cleanup.timer || true
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. The @baseline snapshot — a pinned "this is exactly how the OS shipped"
#    point. Factory reset = roll back to this. Created near-LAST so it captures
#    the finished install (os-release + sddm enabled), but BEFORE the final
#    grub-mkconfig so it appears in the very first boot menu.
#    UN-PRUNABLE: a snapper snapshot with an EMPTY cleanup field is kept forever.
#    Assigning `--cleanup-algorithm number` would do the OPPOSITE — it makes the
#    snapshot eligible for the number-pruner (snap-pac fills that budget fast),
#    so we deliberately pass NO cleanup algorithm. (snapper creates snapshots
#    read-only by default, so no explicit `btrfs property set ... ro` is needed.)
# ─────────────────────────────────────────────────────────────────────────────
pin_baseline() {
  if snapper -c root list 2>/dev/null | grep -q 'baseline'; then
    log "@baseline snapshot already pinned"
    return
  fi
  log "pinning @baseline snapshot (factory-reset point)"
  # No --cleanup-algorithm => empty cleanup field => never auto-pruned.
  snapper -c root create \
    --type single \
    --userdata "important=yes,baseline=yes" \
    --description "KOOMPI @baseline (factory reset point)"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3 + 4. snap-pac is config-free once installed (pacman hooks). grub-btrfs needs
#         its daemon enabled and the GRUB menu regenerated.
# ─────────────────────────────────────────────────────────────────────────────
setup_grub_btrfs() {
  log "enabling grub-btrfs snapshot menu"
  systemctl enable grub-btrfsd.service || true
  # Regenerate GRUB so the snapshot submenu appears. archinstall installed GRUB;
  # we only refresh the config. TODO: confirm grub.cfg path for this target.
  if command -v grub-mkconfig &>/dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg
  fi
}

# ─────────────────────────────────────────────────────────────────────────────
# 4b. Bootable snapshots. grub-btrfs boots a snapshot READ-ONLY; to boot INTO a
#     snapshot as a usable read-write system (the "boot straight into any
#     snapshot" promise) the `grub-btrfs-overlayfs` mkinitcpio hook must be in
#     HOOKS, then the initramfs regenerated. Without it, booting a snapshot drops
#     to an emergency shell. NOTE: this hook needs the `udev` hook, NOT `systemd`.
# ─────────────────────────────────────────────────────────────────────────────
setup_snapshot_boot() {
  local conf=/etc/mkinitcpio.conf
  [ -f "$conf" ] || { log "no $conf — skipping snapshot-boot hook"; return; }
  if grep -q 'grub-btrfs-overlayfs' "$conf"; then
    log "grub-btrfs-overlayfs hook already present"
    return
  fi
  if grep -qE '^HOOKS=.*\bsystemd\b' "$conf"; then
    log "WARNING: mkinitcpio uses the systemd hook; grub-btrfs-overlayfs needs"
    log "         udev. Skipping — snapshot boots stay read-only until reconciled."
    return
  fi
  log "adding grub-btrfs-overlayfs mkinitcpio hook + regenerating initramfs"
  sed -i -E 's/^(HOOKS=\(.*[^ ]) *\)/\1 grub-btrfs-overlayfs)/' "$conf"
  mkinitcpio -P || log "WARNING: mkinitcpio regen failed; snapshot boot may be read-only"
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. Login manager. koompi-branding ships a systemd preset that enables
#    sddm.service; we enable explicitly too (idempotent belt-and-suspenders).
# ─────────────────────────────────────────────────────────────────────────────
enable_login() {
  log "enabling sddm.service"
  systemctl enable sddm.service || true
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. /etc/os-release — KOOMPI identity. Deliberately NOT a package (the
#    `filesystem` package owns the stock file); we overwrite in the target.
#    MUST stay byte-for-byte identical to the live ISO's os-release at
#    sdata/dist-arch/iso/koompi/airootfs/etc/os-release (era "Naga" = v1).
# ─────────────────────────────────────────────────────────────────────────────
write_os_release() {
  log "writing /etc/os-release"
  cat >/etc/os-release <<'EOF'
NAME="KOOMPI OS"
PRETTY_NAME="KOOMPI OS — Naga"
ID=koompi
ID_LIKE=arch
BUILD_ID=rolling
VERSION_CODENAME=naga
ANSI_COLOR="38;2;23;147;209"
HOME_URL="https://koompi.org/"
DOCUMENTATION_URL="https://koompi.org/docs/"
SUPPORT_URL="https://koompi.org/support/"
BUG_REPORT_URL="https://github.com/rithythul/koompi-desktop/issues"
LOGO=koompi
EOF
}

main() {
  log "KOOMPI OS post-install hook starting (SCAFFOLD)"
  ensure_pkgs
  setup_snapper       # snapper config + restore archinstall's @snapshots subvol
  enable_login        # enable sddm BEFORE the baseline so it captures it
  write_os_release    # bake KOOMPI identity into the baseline too
  setup_snapshot_boot # grub-btrfs-overlayfs initramfs hook (bootable snapshots)
  pin_baseline        # snapshot the FINISHED install (un-prunable factory reset)
  setup_grub_btrfs    # LAST: grub-mkconfig enumerates @baseline into the 1st menu
  log "post-install hook done"
}

main "$@"
