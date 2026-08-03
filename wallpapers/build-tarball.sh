#!/usr/bin/env bash
# Packs the curated wallpaper library into the release tarball koompi-branding
# consumes. The images live outside git on purpose: a tarball on a GitHub release
# keeps the repo small and the artifact checksummed.
#
# Usage:
#   wallpapers/build-tarball.sh <source-dir> <version>
#   wallpapers/build-tarball.sh ~/.config/koompi/wallpapers/library 1
#
# Then attach it to a release tagged wallpapers-v<version> on github.com/koompi/
# desktop and put the printed sha256 into sdata/dist-arch/koompi-branding/PKGBUILD.
#
# Layout inside <source-dir> (see STYLE_GUIDE.md): desktop-abstract/*.jpg,
# universe/*.jpg, static/*.jpg, each image with a <name>.source.txt sidecar.
set -euo pipefail

src="${1:?source dir required}"
ver="${2:?version required}"
out="koompi-wallpapers-${ver}.tar.zst"

[ -d "$src" ] || { echo "no such dir: $src" >&2; exit 1; }

count=$(find "$src" -type f \( -name '*.jpg' -o -name '*.png' \) | wc -l)
[ "$count" -gt 0 ] || { echo "no images under $src" >&2; exit 1; }

missing=$(find "$src" -type f \( -name '*.jpg' -o -name '*.png' \) ! -name '*.source.*' \
    | while IFS= read -r f; do [ -f "${f%.*}.source.txt" ] || echo "${f#"$src"/}"; done)
if [ -n "$missing" ]; then
    echo "warning: images without a .source.txt license sidecar:" >&2
    printf '  %s\n' "$missing" >&2
fi

tar --zstd -cf "$out" -C "$src" --transform "s|^\./|koompi-wallpapers/|" .
echo "packed $count images -> $out"
sha256sum "$out"
