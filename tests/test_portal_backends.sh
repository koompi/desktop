#!/usr/bin/env bash
# XDG_DESKTOP_PORTAL_DIR REPLACES the portal search path, it does not extend it, so a
# whitelist makes every backend outside it invisible.
# Asserts on what the repository ships, not on the running session.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOTS="$REPO_ROOT/dots"

fail() { printf '%s\n' "$1" >&2; exit 1; }

# 1. Nothing we ship may pin the portal search path.
offenders="$(grep -rl 'XDG_DESKTOP_PORTAL_DIR' "$DOTS" 2>/dev/null || true)"
[[ -z "$offenders" ]] || fail "dots/ sets XDG_DESKTOP_PORTAL_DIR, which hides every backend it does not list:
$offenders"

# 2. The RemoteDesktop backend must live where xdg-desktop-portal looks by
#    default, which since 1.19 includes XDG_DATA_HOME.
koompi_portal="$DOTS/.local/share/xdg-desktop-portal/portals/koompi.portal"
[[ -f "$koompi_portal" ]] || fail "missing $koompi_portal; the Hyprland session loses its RemoteDesktop backend"
grep -q 'org\.freedesktop\.impl\.portal\.RemoteDesktop' "$koompi_portal" \
    || fail "$koompi_portal no longer declares the RemoteDesktop interface"

#    kde.portal claims RemoteDesktop too once the path is unpinned, and the
#    UseIn tiebreak that would settle it is deprecated.
koompi_conf="$DOTS/.config/xdg-desktop-portal/koompi-portals.conf"
[[ -f "$koompi_conf" ]] || fail "missing $koompi_conf"
grep -q '^org\.freedesktop\.impl\.portal\.RemoteDesktop *= *koompi$' "$koompi_conf" \
    || fail "$koompi_conf does not name koompi for RemoteDesktop; it would be chosen by the deprecated UseIn fallback, or not at all"

# 3. Its D-Bus name must be activatable, and the unit that activates it shipped.
dbus_service="$DOTS/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.koompi.service"
[[ -f "$dbus_service" ]] || fail "missing $dbus_service; the portal name is not activatable"
unit="$(sed -n 's/^SystemdService=//p' "$dbus_service")"
[[ -n "$unit" ]] || fail "$dbus_service names no SystemdService"
[[ -f "$DOTS/.config/systemd/user/$unit" ]] \
    || fail "$dbus_service activates $unit, which dots/ does not ship"

# 4. setup_portals removes the override.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

step() { :; }; info() { :; }; ok() { :; }; warn() { :; }
have() { return 0; }
run() { "$@"; }
XDG_CONFIG_HOME="$tmp/config"
XDG_DATA_HOME="$tmp/share"
# shellcheck disable=SC2032  # setup_portals never calls systemctl through sudo.
systemctl() { :; }

dropin_dir="$XDG_CONFIG_HOME/systemd/user/xdg-desktop-portal.service.d"
mkdir -p "$dropin_dir"
printf '[Service]\nEnvironment=XDG_DESKTOP_PORTAL_DIR=%%h/.local/share/koompi/portals\n' \
    > "$dropin_dir/koompi-remotedesktop.conf"
# shellcheck source=sdata/install/setups.sh
source "$REPO_ROOT/sdata/install/setups.sh" 2>/dev/null || true
declare -F setup_portals >/dev/null || fail 'setups.sh no longer defines setup_portals'
setup_portals >/dev/null 2>&1

[[ ! -e "$dropin_dir/koompi-remotedesktop.conf" ]] \
    || fail 'setup_portals left the XDG_DESKTOP_PORTAL_DIR override in place'

printf 'portal backend tests passed\n'
