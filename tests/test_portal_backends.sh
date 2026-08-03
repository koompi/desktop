#!/usr/bin/env bash
# Two config-shaped ways the Otto bar came up light on a dark desktop, neither
# visible in the portal config itself:
#   1. every bare key in config.toml sat below [[exec_once]], so theme_scheme became
#      a field of the last entry and the compositor never saw it.
#   2. XDG_DESKTOP_PORTAL_DIR REPLACES the portal search path, so a whitelist made
#      otto.portal invisible and xdg-desktop-portal answered from gtk, which reports
#      light.
#
# Asserts on what the repository ships. Whether the running session agrees is a live
# check:
#   busctl --user call org.freedesktop.portal.Desktop /org/freedesktop/portal/desktop \
#          org.freedesktop.portal.Settings ReadAll as 1 org.freedesktop.appearance
# An answer carrying icon-theme came from otto; one carrying contrast came from gtk.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DOTS="$REPO_ROOT/dots"

fail() { printf '%s\n' "$1" >&2; exit 1; }

# 1. Nothing we ship may pin the portal search path.
offenders="$(grep -rl 'XDG_DESKTOP_PORTAL_DIR' "$DOTS" 2>/dev/null || true)"
[[ -z "$offenders" ]] || fail "dots/ sets XDG_DESKTOP_PORTAL_DIR, which hides every backend it does not list:
$offenders"

# 2. The Otto session must name its own Settings backend, or gtk answers for it.
otto_conf="$DOTS/.config/xdg-desktop-portal/otto-portals.conf"
[[ -f "$otto_conf" ]] || fail "missing $otto_conf; the Otto session would fall back to gtk"
grep -q '^org\.freedesktop\.impl\.portal\.Settings *= *otto$' "$otto_conf" \
    || fail "$otto_conf no longer routes Settings to the otto backend"

# 3. The RemoteDesktop backend must live where xdg-desktop-portal looks by
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

# 4. Its D-Bus name must be activatable, and the unit that activates it shipped.
dbus_service="$DOTS/.local/share/dbus-1/services/org.freedesktop.impl.portal.desktop.koompi.service"
[[ -f "$dbus_service" ]] || fail "missing $dbus_service; the portal name is not activatable"
unit="$(sed -n 's/^SystemdService=//p' "$dbus_service")"
[[ -n "$unit" ]] || fail "$dbus_service names no SystemdService"
[[ -f "$DOTS/.config/systemd/user/$unit" ]] \
    || fail "$dbus_service activates $unit, which dots/ does not ship - the same fault otto.portal had"

# 5. theme_scheme must be a top-level key. tomllib is the only honest check:
#    a [table] header above it silently reassigns it and the file still parses.
config_toml="$DOTS/.config/otto/config.toml"
[[ -f "$config_toml" ]] || fail "missing $config_toml"
python3 - "$config_toml" <<'PY' || exit 1
import sys, tomllib
with open(sys.argv[1], "rb") as fh:
    cfg = tomllib.load(fh)
missing = [k for k in ("theme_scheme", "cursor_theme", "font_family") if k not in cfg]
if missing:
    sys.exit(f"{sys.argv[1]}: {', '.join(missing)} is not a top-level key. "
             "A [table] header above a bare key claims it; move the bare keys above "
             "the first table header.")
for entry in cfg.get("exec_once", []):
    stray = set(entry) - {"cmd", "args"}
    if stray:
        sys.exit(f"{sys.argv[1]}: exec_once entry {entry.get('cmd')!r} swallowed "
                 f"{sorted(stray)} - those are top-level keys that fell into a table.")
PY

# 6. setup_portals removes the override, and never removes the hand-made Otto
#    unit before the package that replaces it exists.
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
handmade="$XDG_CONFIG_HOME/systemd/user/xdg-desktop-portal-otto.service"
printf '[Service]\nExecStart=/usr/libexec/xdg-desktop-portal-otto\n' > "$handmade"

# shellcheck source=sdata/install/setups.sh
source "$REPO_ROOT/sdata/install/setups.sh" 2>/dev/null || true
declare -F setup_portals >/dev/null || fail 'setups.sh no longer defines setup_portals'
OTTO_PORTAL_UNIT="$tmp/absent.service" setup_portals >/dev/null 2>&1

[[ ! -e "$dropin_dir/koompi-remotedesktop.conf" ]] \
    || fail 'setup_portals left the XDG_DESKTOP_PORTAL_DIR override in place'
[[ -e "$handmade" ]] \
    || fail 'setup_portals removed the hand-made Otto unit while no packaged unit exists'

packaged="$tmp/packaged.service"
: > "$packaged"
OTTO_PORTAL_UNIT="$packaged" setup_portals >/dev/null 2>&1
[[ ! -e "$handmade" ]] \
    || fail 'setup_portals kept the hand-made Otto unit even though the package now ships one'

printf 'portal backend tests passed\n'
