#!/usr/bin/env bash
# koompi-shell and koompi-hyprland-config copy dots/ into their packages. A
# developer checkout that has built the global-menu daemon carries .zig-cache/
# (367 MB on 2026-08-25) and zig-out/ under the shell tree, gitignored but on
# disk, and both packages used to ship them: into /etc/xdg/quickshell and,
# through /etc/skel, into every new user's $HOME (BUG-AUDIT H3). Runs each
# package() the way makepkg would, against a copy of dots/ with the artefacts
# planted, and checks that none came through and the real payload did.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A fake repo root: the real dots/ plus the artefacts, with the PKGBUILD dirs at
# the same depth as in the repo so "$startdir/../../.." resolves to it.
fake="$tmp/repo"
mkdir -p "$fake/sdata/dist-arch"
cp -a "$REPO_ROOT/dots" "$fake/dots"
cp -a "$REPO_ROOT/sdata/dist-arch/koompi-shell" "$fake/sdata/dist-arch/"
cp -a "$REPO_ROOT/sdata/dist-arch/koompi-hyprland-config" "$fake/sdata/dist-arch/"

shell="$fake/dots/.config/quickshell/koompi"
planted=(
    "$shell/scripts/global-menu/.zig-cache/h/deadbeef/global-menu.o"
    "$shell/scripts/global-menu/zig-out/bin/global-menu"
    "$shell/scripts/__pycache__/helper.cpython-313.pyc"
    "$shell/services/stale.pyc"
    "$shell/.claude/settings.local.json"
    "$shell/.qmlls.ini"
    "$shell/modules/common/widgets/shapes/.git"
    "$fake/dots/.local/bin/.zig-cache/h/deadbeef/tool.o"
    "$fake/dots/.gitignore"
)
for p in "${planted[@]}"; do
    mkdir -p "$(dirname -- "$p")"
    echo junk > "$p"
done

# Sourced and run as makepkg does: top-level assignments, then package() with
# startdir/srcdir/pkgdir set. build() is not run; the one artefact package()
# takes from it is faked.
run_package() {
    local name="$1" srcdir="$2" pkgdir="$3"
    mkdir -p "$srcdir" "$pkgdir"
    (
        set -e
        startdir="$fake/sdata/dist-arch/$name"
        cd "$startdir"
        # shellcheck disable=SC1091  # the PKGBUILD path is computed, not a literal
        source ./PKGBUILD
        package
    ) > "$tmp/$name.log" 2>&1 || { cat "$tmp/$name.log" >&2; fail "$name: package() failed"; }
}

printf '#!/bin/sh\n' > "$tmp/koompi"
install -Dm755 "$tmp/koompi" "$tmp/shell-src/koompi-cli-out/bin/koompi"
run_package koompi-shell "$tmp/shell-src" "$tmp/shell-pkg"
run_package koompi-hyprland-config "$tmp/config-src" "$tmp/config-pkg"

# Nothing from the artefact list reached either package tree.
for pkgdir in "$tmp/shell-pkg" "$tmp/config-pkg"; do
    leaked="$(find "$pkgdir" \( -name .zig-cache -o -name zig-out -o -name __pycache__ \
        -o -name '*.pyc' -o -name .claude -o -name .qmlls.ini -o -name .git -o -name .gitignore \) -print)"
    [[ -z "$leaked" ]] || fail "$(basename -- "$pkgdir") ships build artefacts:
$leaked"
done

# The payload the exclusions must not take with them.
[[ -f "$tmp/shell-pkg/etc/xdg/quickshell/koompi/shell.qml" ]] \
    || fail "koompi-shell lost the shell tree (etc/xdg/quickshell/koompi/shell.qml)"
[[ -f "$tmp/shell-pkg/etc/xdg/quickshell/koompi-quicklook/shell.qml" ]] \
    || fail "koompi-shell lost the quicklook tree"
[[ -f "$tmp/shell-pkg/etc/xdg/quickshell/koompi/scripts/global-menu/build.zig" ]] \
    || fail "koompi-shell lost scripts/global-menu/build.zig next to the pruned cache"
[[ -x "$tmp/shell-pkg/usr/bin/koompi-migrate" ]] \
    || fail "koompi-shell lost the tools (usr/bin/koompi-migrate)"
[[ -f "$tmp/config-pkg/etc/skel/.config/hypr/hyprland.lua" ]] \
    || fail "koompi-hyprland-config lost the hypr config (etc/skel/.config/hypr/hyprland.lua)"
[[ -x "$tmp/config-pkg/etc/skel/.local/bin/koompi-session" ]] \
    || fail "koompi-hyprland-config lost .local/bin (etc/skel/.local/bin/koompi-session)"
[[ -L "$tmp/config-pkg/etc/skel/.local/bin/koompi-wallpaper" ]] \
    || fail "koompi-hyprland-config no longer preserves the koompi-wallpaper symlink"

(( failed == 0 )) || exit 1
echo "ok: package trees carry the dots payload and none of the build artefacts"
