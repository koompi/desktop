#!/usr/bin/env bash
# build-repo.sh — SKELETON: build, GPG-sign, and assemble the signed [koompi]
# pacman repository from the PKGBUILDs under sdata/dist-arch/koompi-*.
#
# This is the first link in the KOOMPI OS ISO chain:
#   signed [koompi] repo  ->  archiso profile (pacman.conf injects [koompi])
#   ->  mkarchiso  ->  the KOOMPI (Zig) installer on the live ISO.
#
# It is intentionally a commented scaffold. The bodies that touch real keys and
# real publish targets are left as TODOs so nothing is wired to production yet.
#
# ─────────────────────────────────────────────────────────────────────────────
# TWO SIGNATURES, NOT ONE  (read before changing anything)
# ─────────────────────────────────────────────────────────────────────────────
# A repo configured with `SigLevel = Required` (what we want) verifies TWO
# independent things:
#   1. each *package*  (koompi-foo-1.0-1-any.pkg.tar.zst  +  .sig)   <- makepkg --sign
#   2. the *database*  (koompi.db.tar.gz                  +  .sig)   <- repo-add --sign
# `repo-add --sign` signs ONLY the database. It does NOT sign the packages.
# If the packages are unsigned, pacman rejects the whole repo under Required.
# That is why step (2) below signs every package and step (3) signs the DB —
# they are deliberately separate operations.
#
# ─────────────────────────────────────────────────────────────────────────────
# CLEAN-CHROOT / devtools is the PRODUCTION build path
# ─────────────────────────────────────────────────────────────────────────────
# In-tree `makepkg` (what this skeleton does by default) works for local repo
# builds because the *-config packages reach ../../../dots via $startdir. But the
# production path is a clean chroot (extra-x86_64-build / makechrootpkg), where
# that relative tree is ABSENT. As noted in the headers of
# koompi-hyprland-config/PKGBUILD and koompi-kde-config/PKGBUILD, a clean-chroot
# build must switch their `source` to a pinned git tag of THIS repo and copy from
# "$srcdir/koompi-desktop/dots". Do that source switch before running this under
# devtools. (See those PKGBUILD "BUILD NOTE" headers for the exact change.)
set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────────
REPO_NAME="koompi"                                  # pacman repo / DB name
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DIST_ARCH="$(cd "$HERE/.." && pwd)"                 # sdata/dist-arch
OUTDIR="${OUTDIR:-$HERE/packages}"                  # built + signed .pkg.tar.zst land here
DBPATH="$OUTDIR/$REPO_NAME.db.tar.gz"

# TODO(GPG): set the KOOMPI packaging signing key id (long fingerprint or email).
#   - Generate once:  gpg --full-generate-key   (RSA 4096, no expiry or rotate-able)
#   - Export public:  gpg --armor --export "$GPG_KEY_ID" > koompi-signing.pub.asc
#   - The PRIVATE key never lives in the repo; in CI it is a secret (see workflow).
GPG_KEY_ID="${GPG_KEY_ID:-TODO_KOOMPI_SIGNING_KEY_ID}"

# TODO(PUBLISH): where the finished repo is served from. This Server= value goes
# verbatim into the archiso pacman.conf and into client /etc/pacman.conf.
#   Candidates: GitHub Releases (https://github.com/koompi/.../releases/download/<tag>)
#               or a mirror host (https://repo.koompi.org/$REPO_NAME/os/x86_64).
PUBLISH_URL="${PUBLISH_URL:-TODO_PUBLISH_BASE_URL}"

# ── 1. Build every koompi-*/PKGBUILD into $OUTDIR ────────────────────────────
build_packages() {
  echo ">> Building every sdata/dist-arch/koompi-*/PKGBUILD into $OUTDIR"
  install -dm755 "$OUTDIR"

  # NOTE: a naive `for d in koompi-*; do makepkg; done` ABORTS, because the meta
  # packages (koompi-base, koompi-desktop-hyprland, koompi-desktop-kde, ...) have
  # depends= on other koompi-* packages that are not in any repo yet, so
  # makepkg's dependency check fails before it can build them.
  #
  # Two correct strategies:
  #   (a) build-only with --nodeps (-d): we only need the .pkg.tar.zst artifact
  #       here; resolution happens at install time on the client. Used below.
  #   (b) PRODUCTION (clean-chroot): build in dependency order and `repo-add` each
  #       result into a local [koompi] before building the metas that need it, so
  #       the chroot can actually resolve and install them. Prefer this for CI.
  #
  # makepkg also REFUSES to run as root. Run this as a normal user (the CI
  # workflow creates a dedicated build user for exactly this reason).
  for pkgdir in "$DIST_ARCH"/koompi-*/; do
    [[ -f "$pkgdir/PKGBUILD" ]] || continue
    echo "   - $(basename "$pkgdir")"
    # --nodeps   : skeleton builds the artifact only (strategy a above)
    # --nobuild? : no — we want the package; --syncdeps is intentionally omitted
    # PKGDEST    : collect all artifacts in one place for signing + repo-add
    (
      cd "$pkgdir"
      PKGDEST="$OUTDIR" makepkg --force --cleanbuild --nodeps
      # PRODUCTION: replace the line above with a clean-chroot invocation, e.g.
      #   PKGDEST="$OUTDIR" makechrootpkg -r /var/lib/archbuild/extra-x86_64 -- --nodeps
      # and remember the *-config source switch (pinned git tag) noted at top.
    )
  done
}

# ── 2. GPG-sign EACH built package ───────────────────────────────────────────
sign_packages() {
  echo ">> Detach-signing every package with key: $GPG_KEY_ID"
  # Each package needs its own detached .sig so SigLevel=Required accepts it.
  # (makepkg --sign during the build does this too; doing it here keeps the
  #  skeleton explicit and re-signable.)
  shopt -s nullglob
  for pkg in "$OUTDIR"/*.pkg.tar.zst; do
    echo "   - sign $(basename "$pkg")"
    gpg --batch --yes --detach-sign --local-user "$GPG_KEY_ID" --output "$pkg.sig" "$pkg"
  done
  shopt -u nullglob
}

# ── 3. Build the signed repo database ────────────────────────────────────────
build_db() {
  echo ">> repo-add: assembling signed $REPO_NAME database"
  # --sign         : sign the DB itself (koompi.db.tar.gz.sig) — DB only, see top.
  # --key          : which key signs the DB.
  # --verify       : verify existing package signatures while adding.
  # repo-add follows the symlink koompi.db -> koompi.db.tar.gz automatically.
  repo-add --sign --verify --key "$GPG_KEY_ID" "$DBPATH" "$OUTDIR"/*.pkg.tar.zst
}

# ── 4. Print the pacman.conf snippet to publish ──────────────────────────────
print_pacman_snippet() {
  cat <<EOF

──────────────────────────────────────────────────────────────────────────────
Add this to /etc/pacman.conf on clients AND to the archiso profile's pacman.conf
(sdata/dist-arch/iso/koompi/pacman.conf) so the live environment can install from
the signed [koompi] repo:

[$REPO_NAME]
SigLevel = Required
Server = $PUBLISH_URL

CLIENT KEY IMPORT (required once, before SigLevel=Required will trust anything):
The signing key must be in pacman's OWN keyring (pacman-key), which is separate
from any user gpg keyring:

  sudo pacman-key --recv-keys $GPG_KEY_ID          # or: --add koompi-signing.pub.asc
  sudo pacman-key --lsign-key $GPG_KEY_ID          # locally sign = trust it

On the ISO, ship koompi-signing.pub.asc in airootfs and run those two commands in
the archiso pacman hook / profile so the live system trusts [koompi] out of the box.
──────────────────────────────────────────────────────────────────────────────
EOF
}

main() {
  build_packages
  sign_packages
  build_db
  print_pacman_snippet
  echo ">> Done. Publish the contents of: $OUTDIR  ->  $PUBLISH_URL"
}

main "$@"
