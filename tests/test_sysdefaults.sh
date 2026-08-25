#!/usr/bin/env bash
# koompi-sysdefaults is three defaults in seven vendor drop-ins: swap on zram,
# systemd-oomd allowed to kill only the user manager's app.slice, and a 5 s stop
# timeout. Each is inert if its file is misnamed, lands in the wrong directory,
# or carries a key systemd does not know (systemd logs "Unknown key" and moves
# on), so the checks here are on the built package and on what systemd makes of
# it, not on the source tree alone.
#
# Builds the package into a temp dir when makepkg is here; touches nothing on
# the machine.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKG_DIR="$ROOT/sdata/dist-arch/koompi-sysdefaults"
FILES="$PKG_DIR/files"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Relative to /usr/lib, both in files/ and in the package.
ZRAM=systemd/zram-generator.conf.d/90-koompi.conf
ZSWAP=tmpfiles.d/koompi-zswap.conf
OOMD_SLICE=systemd/user/app.slice.d/10-koompi-oomd.conf
OOMD_CONF=systemd/oomd.conf.d/10-koompi.conf
STOP_SYSTEM=systemd/system.conf.d/10-koompi-faster-shutdown.conf
STOP_USER=systemd/system/user@.service.d/10-koompi-faster-shutdown.conf
PRESET=systemd/system-preset/80-koompi-sysdefaults.preset
SHIPPED=("$ZRAM" "$ZSWAP" "$OOMD_SLICE" "$OOMD_CONF" "$STOP_SYSTEM" "$STOP_USER" "$PRESET")

# 1. Every file says exactly what it must. Whole-line matches: a key with a
#    typo or a stray suffix is what systemd ignores.
expect() {
    [[ -f "$FILES/$1" ]] || fail "$1 is not in the package source"
    grep -Fxq -- "$2" "$FILES/$1" || fail "$1 does not carry '$2'"
}
expect "$ZRAM" 'zram-size = ram'
expect "$ZRAM" 'compression-algorithm = zstd'
expect "$ZRAM" 'swap-priority = 100'
expect "$ZSWAP" 'w! /sys/module/zswap/parameters/enabled - - - - N'
expect "$OOMD_SLICE" 'ManagedOOMMemoryPressure=kill'
expect "$OOMD_SLICE" 'ManagedOOMSwap=kill'
expect "$OOMD_CONF" 'DefaultMemoryPressureLimit=50%'
expect "$OOMD_CONF" 'DefaultMemoryPressureDurationSec=20s'
expect "$STOP_SYSTEM" 'DefaultTimeoutStopSec=5s'
expect "$STOP_USER" 'TimeoutStopSec=5s'
expect "$PRESET" 'enable systemd-oomd.service'

# 2. Kill candidacy is set on app.slice and nowhere else. Hyprland and the
#    shell run in the login session's scope; any candidacy on user@.service,
#    user.slice or session.slice puts them in the victim pool, which is the
#    crash these files exist to prevent.
candidates="$(grep -rlE '^ManagedOOM(MemoryPressure|Swap)=' \
    "$ROOT/sdata" "$ROOT/dots/.config/systemd" "$ROOT/installer" 2>/dev/null | sort)"
[[ "$candidates" == "$FILES/$OOMD_SLICE" ]] \
    || fail "oomd candidacy is set outside app.slice, which can select the compositor: ${candidates:-none}"

# 3. Wiring. The package needs zram-generator or the zram file is inert; the
#    Hyprland edition has to pull the package in; the from-git route has to
#    install the same files and enable the daemon that reads them.
# A PKGBUILD's depends=() only exists once the file is sourced, so read it in
# a child bash rather than here, where it would be an unassigned reference.
pkgbuild_depends() {
    bash -c 'source "$1" 2>/dev/null; printf "%s\n" "${depends[@]}"' _ "$1"
}
pkgbuild_depends "$PKG_DIR/PKGBUILD" | grep -Fxq zram-generator \
    || fail "koompi-sysdefaults does not depend on zram-generator"
pkgbuild_depends "$ROOT/sdata/dist-arch/koompi-desktop-hyprland/PKGBUILD" | grep -Fxq koompi-sysdefaults \
    || fail "koompi-desktop-hyprland does not depend on koompi-sysdefaults"

setups="$ROOT/sdata/install/setups.sh"
fn="$(sed -n '/^setup_low_ram_defaults() {/,/^}/p' "$setups")"
[[ -n "$fn" ]] || fail "setups.sh has no setup_low_ram_defaults"
sed -n '/^run_setups() {/,/^}/p' "$setups" | grep -Fxq '    setup_low_ram_defaults' \
    || fail "run_setups never calls setup_low_ram_defaults"
grep -Fq 'koompi-sysdefaults/files' <<< "$fn" \
    || fail "setup_low_ram_defaults does not install from the package's files/, so the two routes can drift"
grep -Eq 'install -Dm644 .*"/usr/local/lib/' <<< "$fn" \
    || fail "setup_low_ram_defaults does not install under /usr/local/lib"
grep -Eq 'install -Dm644 .*"/usr/lib/' <<< "$fn" \
    && fail "setup_low_ram_defaults writes under /usr/lib, which pacman owns: a later package install fails on 'exists in filesystem'"
grep -Fq 'systemctl enable systemd-oomd.service' <<< "$fn" \
    || fail "setup_low_ram_defaults ships the oomd drop-ins with the daemon that reads them disabled"
grep -Fq 'systemctl restart systemd-oomd.service' <<< "$fn" \
    || fail "oomd reads its thresholds at startup only; without a restart a running daemon keeps 60% / 30 s"
grep -Fq 'systemctl --user daemon-reload' <<< "$fn" \
    || fail "the user manager reports app.slice candidacy only after a reload"

# 4. The built package: the seven files at their /usr/lib paths, nothing else,
#    and the dependency recorded in the artifact.
analyze_root="$tmp/root"
if command -v makepkg >/dev/null 2>&1; then
    if ! (cd "$PKG_DIR" && BUILDDIR="$tmp/build" PKGDEST="$tmp/pkgs" SRCDEST="$tmp/src" \
            makepkg --force --cleanbuild --nodeps > "$tmp/makepkg.log" 2>&1); then
        cat "$tmp/makepkg.log" >&2
        fail "makepkg could not build koompi-sysdefaults"
    fi
    pkg="$(find "$tmp/pkgs" -name 'koompi-sysdefaults-*.pkg.tar.*' ! -name '*-debug-*' | head -n 1)"
    [[ -n "$pkg" ]] || fail "makepkg produced no koompi-sysdefaults package"

    bsdtar -tf "$pkg" > "$tmp/listing"
    printf 'usr/lib/%s\n' "${SHIPPED[@]}" | sort > "$tmp/want"
    grep -v '/$' "$tmp/listing" | grep -v '^\.' | sort > "$tmp/got"
    diff -u "$tmp/want" "$tmp/got" >&2 \
        || fail "the package does not ship exactly the seven drop-ins"
    bsdtar -xOf "$pkg" .PKGINFO | grep -Fxq 'depend = zram-generator' \
        || fail "the built package does not record the zram-generator dependency"

    mkdir -p "$analyze_root"
    bsdtar -xf "$pkg" -C "$analyze_root" --exclude '.PKGINFO' --exclude '.MTREE' --exclude '.BUILDINFO'
    echo "built $(basename -- "$pkg")"
else
    echo "skip: makepkg not here; checking the source tree instead of the package"
    mkdir -p "$analyze_root/usr/lib"
    cp -a "$FILES/." "$analyze_root/usr/lib/"
fi

# 5. What systemd makes of it. cat-config resolves the same search path the
#    daemons use, so a drop-in in the wrong directory shows up as absent.
#    verify parses the unit drop-ins with the real unit parser; an unknown key
#    is only a warning there, so the output is checked as well as the status.
if ! command -v systemd-analyze >/dev/null 2>&1; then
    echo "skip: systemd-analyze not here; drop-ins not verified"
    echo "ok test_sysdefaults.sh"
    exit 0
fi

cat_config() {
    local out
    out="$(systemd-analyze --root="$analyze_root" cat-config "$1" 2>&1)" \
        || fail "systemd-analyze cat-config $1 failed: $out"
    grep -Fxq -- "$2" <<< "$out" \
        || fail "systemd-analyze cat-config $1 does not resolve '$2'"
}
cat_config systemd/system.conf 'DefaultTimeoutStopSec=5s'
cat_config systemd/oomd.conf 'DefaultMemoryPressureLimit=50%'
cat_config systemd/oomd.conf 'DefaultMemoryPressureDurationSec=20s'
cat_config systemd/zram-generator.conf 'zram-size = ram'
cat_config tmpfiles.d 'w! /sys/module/zswap/parameters/enabled - - - - N'

# The stock units the drop-ins attach to, so verify has something to load.
if [[ -f /usr/lib/systemd/user/app.slice ]]; then
    install -Dm644 /usr/lib/systemd/user/app.slice "$analyze_root/usr/lib/systemd/user/app.slice"
else
    install -Dm644 /dev/stdin "$analyze_root/usr/lib/systemd/user/app.slice" \
        <<< $'[Unit]\nDescription=User Application Slice\n\n[Slice]\nCPUWeight=100'
fi
verify() { # unit path dir, extra args..., unit
    local dir="$1"; shift
    local out rc=0
    out="$(SYSTEMD_UNIT_PATH="$analyze_root/usr/lib/systemd/$dir" \
        systemd-analyze --man=no --recursive-errors=no "$@" 2>&1)" || rc=$?
    [[ $rc -eq 0 ]] || fail "systemd-analyze verify ${*: -1} failed ($rc): $out"
    grep -Eiq 'unknown|ignoring|failed' <<< "$out" \
        && fail "systemd-analyze verify ${*: -1} rejected a drop-in line: $out"
    return 0
}
verify user --user verify app.slice
if [[ -f /usr/lib/systemd/system/user@.service ]]; then
    install -Dm644 /usr/lib/systemd/system/user@.service "$analyze_root/usr/lib/systemd/system/user@.service"
    verify system verify user@1000.service
else
    echo "skip: no stock user@.service here; its drop-in checked by cat-config only"
    cat_config systemd/system/user@.service.d 'TimeoutStopSec=5s'
fi

echo "ok test_sysdefaults.sh"
