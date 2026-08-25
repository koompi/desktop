#!/usr/bin/env bash
# The greeter must offer KOOMPI and nothing else. Every part of that is a
# separate file, so this checks they still agree with each other.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DROPIN="$ROOT/sdata/dist-arch/koompi-session/sddm-sessiondir.conf"
PKGBUILD="$ROOT/sdata/dist-arch/koompi-session/PKGBUILD"
SETUPS="$ROOT/sdata/install/setups/session.sh"
UNINSTALL="$ROOT/sdata/install/uninstall.sh"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

sessiondir="$(sed -n 's/^SessionDir=\(.*\)$/\1/p' "$DROPIN" | head -1)"
[[ -n "$sessiondir" ]] || fail "no Wayland SessionDir in the drop-in"

# The whole point: no directory any other package writes to.
IFS=',' read -ra dirs <<< "$sessiondir"
for d in "${dirs[@]}"; do
    case "$d" in
        /usr/share/koompi/*|/usr/local/share/*) ;;
        *) fail "SessionDir includes $d, which other packages install into" ;;
    esac
done

grep -q '^SessionDir=/usr/share/koompi/xsessions$' "$DROPIN" \
    || fail "X11 SessionDir is not pinned to a koompi-owned path"

# A pinned SessionDir with nothing in it is an unloggable machine, so both
# install paths have to put an entry there and the drop-in has to ship.
grep -q 'usr/share/koompi/wayland-sessions/koompi.desktop' "$PKGBUILD" \
    || fail "koompi-session does not install the entry the greeter reads"
grep -q 'etc/sddm.conf.d/20-koompi-session.conf' "$PKGBUILD" \
    || fail "koompi-session does not ship the SDDM drop-in"
grep -q 'usr/share/koompi/wayland-sessions/koompi.desktop' "$SETUPS" \
    || fail "setups.sh does not install the entry the greeter reads"
grep -q 'sddm-sessiondir.conf' "$SETUPS" \
    || fail "setups.sh does not install the SDDM drop-in"

# ...and removing it has to remove the restriction with it.
grep -q '/etc/sddm.conf.d/20-koompi-session.conf' "$UNINSTALL" \
    || fail "uninstall refuses to remove the drop-in, leaving a greeter with no sessions"
grep -q '/usr/share/koompi/wayland-sessions/koompi.desktop' "$UNINSTALL" \
    || fail "uninstall refuses to remove the greeter's session entry"
grep -n 'dm_entry\|20-koompi-session' "$SETUPS" | grep -q 'SYSTEM_MANIFEST' \
    || grep -A6 'SYSTEM_MANIFEST"$' "$SETUPS" | grep -q 'dm_entry' \
    || fail "setups.sh does not record the new system paths in the manifest"

echo "ok"
