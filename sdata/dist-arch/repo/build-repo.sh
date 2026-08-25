#!/usr/bin/env bash
# Skeleton. Bodies touching real keys and publish targets are still TODO.
#
# SigLevel=Required verifies packages and database separately. repo-add --sign signs
# only the DB, so packages need makepkg --sign too or pacman rejects the lot.
#
# Clean-chroot builds have no ../../../dots, so the *-config PKGBUILDs must switch
# source to a pinned git tag first. See their BUILD NOTE headers.
set -euo pipefail

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

build_packages() {
  echo ">> Building every sdata/dist-arch/*/PKGBUILD into $OUTDIR"
  install -dm755 "$OUTDIR"

  # A naive `for d in koompi-*; do makepkg; done` aborts: the metas depend on other
  # koompi-* packages that are in no repo yet, so makepkg's dependency check fails
  # first. Build-only with --nodeps (-d) below, since only the artifact is wanted here.
  # For CI prefer a clean chroot: build in dependency order and repo-add each result
  # into a local [koompi] before the metas that need it.
  # makepkg also refuses to run as root - the CI workflow makes a build user.
  # Every directory with a PKGBUILD, not koompi-*/: ttf-koompi-star lives here too.
  for pkgdir in "$DIST_ARCH"/*/; do
    [[ -f "$pkgdir/PKGBUILD" ]] || continue
    echo "   - $(basename "$pkgdir")"
    # --nodeps   : skeleton builds the artifact only (strategy a above)
    # --nobuild? : no - we want the package; --syncdeps is intentionally omitted
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

build_db() {
  echo ">> repo-add: assembling signed $REPO_NAME database"
  # --sign         : sign the DB itself (koompi.db.tar.gz.sig) - DB only, see top.
  # --key          : which key signs the DB.
  # --verify       : verify existing package signatures while adding.
  # repo-add follows the symlink koompi.db -> koompi.db.tar.gz automatically.
  repo-add --sign --verify --key "$GPG_KEY_ID" "$DBPATH" "$OUTDIR"/*.pkg.tar.zst
}

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
