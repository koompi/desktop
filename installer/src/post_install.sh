#!/usr/bin/env bash
# SCAFFOLD, UNTESTED. Runs inside the pacstrapped target via arch-chroot /mnt.
# Do NOT run on a live system. Idempotent: every step checks before it acts.
#
# @baseline is the factory-reset point: snapper -c root rollback <N>, or pick it
# from the grub-btrfs menu.

set -euo pipefail

log() { printf '[koompi-installer] %s\n' "$*"; }

# 0. Packages the post-install needs. archinstall pacstrapped the edition
#    metapackage already; these are the snapshot-tooling extras.
#    REVIEW: pin versions on the ISO if reproducibility matters.
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

# 1. snapper config for root. archinstall's btrfs layout already made @ and a
#    .snapshots subvol, so `snapper create-config` must not make its own. Create the
#    config file, then point it at the existing layout.
#    REVIEW: the fiddliest interaction with archinstall's layout.
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
  # create-config just made its own .snapshots nested inside @. Delete it and restore
  # archinstall's real @snapshots at /.snapshots, or every snapshot including
  # @baseline lands in the nested subvol and is hidden the moment fstab remounts
  # @snapshots over it - silently losing the factory-reset point.
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

# 2. @baseline: the pinned "how the OS shipped" point. Created near-last so it
#    captures the finished install, but before the final grub-mkconfig so it appears
#    in the first boot menu.
#    An EMPTY cleanup field is what keeps it forever. `--cleanup-algorithm number`
#    would do the opposite and hand it to the pruner snap-pac fills fast.
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

# 3 + 4. snap-pac is config-free once installed (pacman hooks). grub-btrfs needs
#         its daemon enabled and the GRUB menu regenerated.
setup_grub_btrfs() {
  log "enabling grub-btrfs snapshot menu"
  systemctl enable grub-btrfsd.service || true
  # Regenerate GRUB so the snapshot submenu appears. archinstall installed GRUB;
  # we only refresh the config. TODO: confirm grub.cfg path for this target.
  if command -v grub-mkconfig &>/dev/null; then
    grub-mkconfig -o /boot/grub/grub.cfg
    quiet_grub_entries
  fi
}

# 4a. /etc/grub.d/10_linux emits "Loading Linux ..." into every menuentry
#     unconditionally. Arch carries no quiet_boot knob (that is a Fedora patch), so
#     stripping the generated file is the only lever short of shipping our own
#     10_linux, which would collide with the grub package on every update.
#     Runs after EVERY grub-mkconfig, never standalone: a later regeneration puts
#     the lines back. Matches the English string grub-mkconfig emits under the C
#     locale; a localised run leaves them and says so.
quiet_grub_entries() {
  local cfg="${KOOMPI_GRUB_CFG:-/boot/grub/grub.cfg}"
  [ -f "$cfg" ] || return 0
  if ! grep -q "^[[:space:]]*echo[[:space:]]*'Loading " "$cfg"; then
    log "no 'Loading ...' lines in $cfg (localised grub-mkconfig?) — leaving it alone"
    return 0
  fi
  sed -i "/^[[:space:]]*echo[[:space:]]*'Loading /d" "$cfg"
  # A malformed grub.cfg is an unbootable machine, so prove it still parses.
  if command -v grub-script-check &>/dev/null && ! grub-script-check "$cfg"; then
    log "ERROR: $cfg failed grub-script-check after the strip; regenerating"
    grub-mkconfig -o "$cfg"
    return 1
  fi
  log "silenced the GRUB 'Loading ...' lines"
}

# 4b. grub-btrfs boots a snapshot read-only. Booting INTO one as a usable
#     read-write system needs the grub-btrfs-overlayfs mkinitcpio hook in HOOKS and
#     a regenerated initramfs, or it drops to an emergency shell. That hook needs
#     the `udev` hook, NOT `systemd`.
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

# 5. Login manager. koompi-branding ships a systemd preset that enables
#    sddm.service; we enable explicitly too (idempotent belt-and-suspenders).
enable_login() {
  log "enabling sddm.service"
  systemctl enable sddm.service || true
}

# 5a. Firewall rules. The chroot shares the live ISO's kernel, so `ufw enable`
#     would load rules into the installer's firewall; with ufw down every other
#     command only edits /etc/ufw, and ENABLED=yes is what ufw.service reads at
#     first boot (omarchy's firewall.sh does the same).
setup_firewall() {
  local conf="${KOOMPI_UFW_CONF:-/etc/ufw/ufw.conf}"
  if ! command -v ufw &>/dev/null; then
    log "WARNING: ufw is not installed; incoming connections stay open"
    return
  fi
  log "firewall: deny incoming, allow KDE Connect and LocalSend"
  if ! ufw default deny incoming \
    || ! ufw default allow outgoing \
    || ! ufw allow KOOMPI-KDEConnect \
    || ! ufw allow KOOMPI-LocalSend; then
    log "WARNING: writing the ufw rules failed; the firewall stays off"
    return
  fi
  sed -i 's/^ENABLED=.*/ENABLED=yes/' "$conf"
  systemctl enable ufw.service || true
}

# 5b. enable-only, as the snapper timers: a chroot cannot start units.
enable_firmware_refresh() {
  log "enabling fwupd-refresh.timer"
  systemctl enable fwupd-refresh.timer || true
}

# 6. /etc/os-release - KOOMPI identity. Deliberately NOT a package (the
#    `filesystem` package owns the stock file); we overwrite in the target.
#    MUST stay byte-for-byte identical to the live ISO's os-release at
#    sdata/dist-arch/iso/koompi/airootfs/etc/os-release (era "Naga" = v1).
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
BUG_REPORT_URL="https://github.com/koompi/desktop/issues"
LOGO=koompi
EOF
}

main() {
  log "KOOMPI OS post-install hook starting (SCAFFOLD)"
  ensure_pkgs
  setup_snapper       # snapper config + restore archinstall's @snapshots subvol
  enable_login        # enable sddm BEFORE the baseline so it captures it
  setup_firewall      # rules + ENABLED=yes into the baseline too
  enable_firmware_refresh
  write_os_release    # bake KOOMPI identity into the baseline too
  setup_snapshot_boot # grub-btrfs-overlayfs initramfs hook (bootable snapshots)
  pin_baseline        # snapshot the FINISHED install (un-prunable factory reset)
  setup_grub_btrfs    # LAST: grub-mkconfig enumerates @baseline into the 1st menu
  log "post-install hook done"
}

# Sourced by tests/test_grub_quiet.sh, which needs the functions without the run.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
