#!/usr/bin/env bash
# Three families have to reach the right recipe, and the zig floor has to hold.
#
# The floor is the part that bit: Debian 13 packages no zig at all and Ubuntu's
# `zig` metapackage still points at 0.14, so a plain `have zig` finds a compiler
# that cannot build the global-menu daemon and the build fails instead of being
# skipped. Nothing here touches the network or a package manager.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

DRY_RUN=true ASSUME_YES=true
# shellcheck source=sdata/lib/common.sh
source "$ROOT/sdata/lib/common.sh"
# shellcheck source=sdata/lib/distro.sh
source "$ROOT/sdata/lib/distro.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. Every family, and the derivatives that only arrive through ID_LIKE.
check_group() {
    local name="$1" id="$2" like="$3" want="$4"
    { printf 'ID=%s\n' "$id"; [[ -n "$like" ]] && printf 'ID_LIKE="%s"\n' "$like"; } > "$tmp/os-release"
    KOOMPI_OS_RELEASE="$tmp/os-release" detect_distro
    [[ "$OS_GROUP_ID" == "$want" ]] \
        || fail "$name mapped to '${OS_GROUP_ID:-none}', expected '${want:-none}'"
}
check_group arch        arch                ''              arch
check_group koompi      koompi              ''              arch
check_group manjaro     manjaro             'arch'          arch
check_group fedora      fedora              ''              fedora
check_group rocky       rocky               'rhel centos fedora' fedora
check_group debian      debian              ''              debian
check_group ubuntu      ubuntu              'debian'        debian
check_group mint        linuxmint           'ubuntu debian' debian
# An unknown distro must resolve to nothing rather than guess a package manager.
check_group tumbleweed  opensuse-tumbleweed 'suse'          ''

# 2. Every group a distro can land in needs its recipes and lists on disk, or
#    detection succeeds and the install dies two steps later.
for group in arch fedora debian; do
    for f in install-deps.sh install-apps.sh; do
        [[ -f "$ROOT/sdata/dist-$group/$f" ]] || fail "missing sdata/dist-$group/$f"
    done
done
for f in packages.list packages-apps.list; do
    [[ -f "$ROOT/sdata/dist-fedora/$f" ]] || fail "missing sdata/dist-fedora/$f"
    [[ -f "$ROOT/sdata/dist-debian/$f" ]] || fail "missing sdata/dist-debian/$f"
done

# 3. The zig floor. A stub stands in for the distro's compiler, behind a PATH
#    holding only that stub and the one tool zig_usable itself runs - otherwise
#    this host's real zig answers, and the no-zig case can never be reached.
mkdir -p "$tmp/bin"
ln -s "$(command -v sort)" "$tmp/bin/sort"

zig_says() {
    printf '#!/bin/sh\necho %s\n' "$1" > "$tmp/bin/zig"
    chmod +x "$tmp/bin/zig"
}
floor_accepts() { ( PATH="$tmp/bin"; zig_usable ); }

zig_says 0.14.1; floor_accepts && fail "zig 0.14.1 passed a ${ZIG_MIN} floor"
zig_says 0.15.2; floor_accepts && fail "zig 0.15.2 passed a ${ZIG_MIN} floor"
zig_says 0.16.0; floor_accepts || fail "zig 0.16.0 failed a ${ZIG_MIN} floor"
zig_says 0.17.0; floor_accepts || fail "zig 0.17.0 failed a ${ZIG_MIN} floor"
zig_says 1.0.0;  floor_accepts || fail "zig 1.0.0 failed a ${ZIG_MIN} floor"
# A pre-release is not the release it names, and the daemon needs the release.
zig_says 0.16.0-dev.164+bc7955306; floor_accepts && fail "a 0.16.0-dev build passed the floor"
# ...but a pre-release of the next one is still above this floor.
zig_says 0.17.0-dev.1+aaaaaaaaa;   floor_accepts || fail "a 0.17.0-dev build failed the floor"
rm -f "$tmp/bin/zig"; floor_accepts && fail "no zig at all passed the floor"

# 4. The floor has to match what the daemon actually declares, or one moves
#    without the other and the check starts lying.
declared="$(sed -n 's/.*\.minimum_zig_version = "\([^"]*\)".*/\1/p' \
    "$ROOT/dots/.config/quickshell/koompi/scripts/global-menu/build.zig.zon")"
[[ "$declared" == "$ZIG_MIN" ]] \
    || fail "global-menu declares zig $declared but common.sh floors at $ZIG_MIN"

# 4b. Same trap on the rust side. cargo_usable is a plain version compare, so
#     the pre-release trap zig has does not apply, but the drift one does.
cargo_says() {
    printf '#!/bin/sh\necho "cargo %s (c980f4866 2026-06-30)"\n' "$1" > "$tmp/bin/cargo"
    chmod +x "$tmp/bin/cargo"
}
cargo_floor_accepts() { ( PATH="$tmp/bin"; cargo_usable ); }
ln -sf "$(command -v awk)" "$tmp/bin/awk"

cargo_says 1.75.0; cargo_floor_accepts && fail "cargo 1.75.0 passed a ${RUST_MIN} floor"
cargo_says 1.87.0; cargo_floor_accepts || fail "cargo 1.87.0 failed a ${RUST_MIN} floor"
cargo_says 1.97.1; cargo_floor_accepts || fail "cargo 1.97.1 failed a ${RUST_MIN} floor"
rm -f "$tmp/bin/cargo"; cargo_floor_accepts && fail "no cargo at all passed the floor"

rust_declared="$(sed -n 's/^rust-version = "\([^"]*\)".*/\1/p' "$ROOT/globalmenu/Cargo.toml")"
[[ "$rust_declared" == "$RUST_MIN" ]] \
    || fail "globalmenu declares rust $rust_declared but common.sh floors at $RUST_MIN"

# 5. Debian and Ubuntu cannot rely on the packaged zig, so the recipe has to
#    fetch one; Fedora calls it too so a future release falling behind is a
#    download rather than a missing global menu.
grep -q '^install_zig$' "$ROOT/sdata/dist-debian/install-deps.sh" \
    || fail "the Debian recipe never calls install_zig; Debian 13 has no zig package"
grep -q '^install_zig$' "$ROOT/sdata/dist-fedora/install-deps.sh" \
    || fail "the Fedora recipe never calls install_zig"
grep -q 'install_zig()' "$ROOT/sdata/lib/from-source.sh" \
    || fail "from-source.sh does not define install_zig"

# 6. Names that resolved to nothing on a current release, each verified in a
#    container. Cheap to re-break, expensive to notice.
grep -q '^xorg-x11-utils' "$ROOT/sdata/dist-fedora/packages.list" \
    && fail "xorg-x11-utils is back; Fedora 41+ resolves it to nothing, so xprop goes missing"
grep -q '^xprop' "$ROOT/sdata/dist-fedora/packages.list" \
    || fail "Fedora no longer asks for xprop; the global menu cannot read menu addresses"

# 7. The apt availability filter. A name apt cannot install has to be skipped
#    with a warning, because apt fails the whole transaction on one bad name and
#    the batch is 112 packages. A stub apt-cache stands in for the archive.
# shellcheck source=sdata/lib/debian.sh
source "$ROOT/sdata/lib/debian.sh"
cat > "$tmp/bin/apt-cache" <<'STUB'
#!/bin/sh
# $1 is the subcommand, $2 the package.
case "$2" in
    # A real package.
    hyprland) real='1:0.55.2+ds-1~bpo13+1' ;;
    # In contrib, which a stock install does not enable. `apt-cache show` still
    # answers for it because packages.list's neighbours depend on it.
    translate-shell) real='' ;;
    # Not in this archive at all under any name.
    *) [ "$1" = show ] && exit 1; echo "N: Unable to locate package $2" >&2; exit 0 ;;
esac
if [ "$1" = show ]; then echo "Package: $2"; exit 0; fi
echo "$2:"
echo "  Installed: (none)"
if [ -n "$real" ]; then echo "  Candidate: $real"; else echo "  Candidate: (none)"; fi
STUB
chmod +x "$tmp/bin/apt-cache"

with_stub() { ( PATH="$tmp/bin:$PATH"; "$@" ); }
with_stub debian_candidate hyprland >/dev/null \
    || fail "debian_candidate rejected a package apt offers a version for"
[[ "$(with_stub debian_candidate hyprland)" == '1:0.55.2+ds-1~bpo13+1' ]] \
    || fail "debian_candidate did not return the candidate version"
with_stub debian_candidate translate-shell >/dev/null \
    && fail "debian_candidate accepted a package with no installation candidate; apt-get would abort the whole batch on it"
with_stub debian_candidate no-such-package >/dev/null \
    && fail "debian_candidate accepted a package apt has never heard of"
grep -q 'apt-cache show' "$ROOT/sdata/dist-debian/install-deps.sh" \
    && fail "the Debian recipe is back to filtering on 'apt-cache show', which answers for any name a neighbour depends on"

# 8. Debian's contrib has to be enabled for the release itself. Backports does
#    not cover it, and translate-shell is in trixie/contrib and nowhere else.
grep -q 'koompi-components.list' "$ROOT/sdata/dist-debian/install-deps.sh" \
    || fail "the Debian recipe no longer enables contrib for the release; translate-shell has no candidate in main"
grep -q 'OS_VERSION_CODENAME' "$ROOT/sdata/lib/distro.sh" \
    || fail "distro.sh stopped exporting OS_VERSION_CODENAME, which names the apt suite"
: > "$tmp/os-release"
printf 'ID=debian\nVERSION_ID="13"\nVERSION_CODENAME=trixie\n' > "$tmp/os-release"
KOOMPI_OS_RELEASE="$tmp/os-release" detect_distro
[[ "$OS_VERSION_CODENAME" == trixie ]] \
    || fail "detect_distro read the codename as '${OS_VERSION_CODENAME:-empty}', expected trixie"

echo "ok"
