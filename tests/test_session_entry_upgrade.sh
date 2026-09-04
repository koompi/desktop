#!/usr/bin/env bash
# Which /usr/share/wayland-sessions entries setups/session.sh may replace.
# Too narrow and a KOOMPI machine stays on start-hyprland, without
# koompi-session's PATH, so every koompi-launch keybind exits 127 and no app
# opens; too wide and it overwrites another desktop's session entry.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETUPS="$REPO_ROOT/sdata/install/setups/session.sh"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

# shellcheck source=/dev/null
source "$SETUPS" || fail "session.sh cannot be sourced on its own"
declare -F koompi_session_entry_is_ours >/dev/null \
    || fail "session.sh does not define koompi_session_entry_is_ours"

ours() {
    local name=$1 body=$2
    printf '%s' "$body" > "$tmp/$name"
    koompi_session_entry_is_ours "$tmp/$name"
}

koompi_session_entry_is_ours "$tmp/absent.desktop" \
    || fail "a missing entry must be installable"

ours marked.desktop '[Desktop Entry]
Name=KOOMPI
Exec=/usr/local/bin/koompi-session
DesktopNames=KOOMPI;Hyprland
X-KOOMPI-Managed=true
' || fail "the marker is not recognised"

ours stale.desktop '[Desktop Entry]
Name=KOOMPI
Comment=KOOMPI desktop powered by Hyprland
Exec=/usr/bin/start-hyprland
TryExec=/usr/bin/start-hyprland
DesktopNames=KOOMPI;Hyprland
' || fail "a pre-marker KOOMPI entry is skipped, so start-hyprland is never repaired"

ours trailing.desktop '[Desktop Entry]
Name=KOOMPI
DesktopNames=Hyprland;KOOMPI
' || fail "KOOMPI last in DesktopNames is still our session"

ours foreign.desktop '[Desktop Entry]
Name=Sway
Exec=/usr/bin/sway
DesktopNames=sway;wlroots
' && fail "somebody else's session entry would be overwritten"

ours mentions.desktop '[Desktop Entry]
Name=GNOME on KOOMPI OS
Comment=KOOMPI
Exec=/usr/bin/gnome-session
DesktopNames=GNOME
' && fail "an entry that only mentions KOOMPI would be overwritten"

koompi_session_entry_is_ours \
    "$REPO_ROOT/dots/.local/share/wayland-sessions/koompi.desktop" \
    || fail "our own shipped entry is not recognised as ours"

# shellcheck disable=SC2016  # literal source text, not expansions
{
    grep -q 'koompi_session_entry_is_ours "$entry"' "$SETUPS" \
        || fail "setup_system_session does not gate on koompi_session_entry_is_ours"
    grep -q 'sudo cp -a "$entry"' "$SETUPS" \
        || fail "a pre-marker entry is replaced without keeping a copy"
}

echo "ok"
