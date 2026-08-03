#!/usr/bin/env bash
# Password to desktop is three programs handing one colour to each other: the greeter
# fades to it, Hyprland clears to it, the shell dissolves the wallpaper up out of it.
# Three config languages with nothing shared, so this is the only thing keeping them
# equal.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
THEME="$ROOT/sdata/dist-arch/koompi-branding/files/sddm/theme/theme.conf"
GREETER="$ROOT/sdata/dist-arch/koompi-branding/files/sddm/theme/Main.qml"
HYPR="$ROOT/dots/.config/hypr/hyprland/colors.lua"
BG="$ROOT/dots/.config/quickshell/koompi/modules/koompi/background/Background.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

greeter="$(sed -n 's/^transitionColor=#\{0,1\}\([0-9a-fA-F]\{6\}\).*/\1/p' "$THEME" | head -1)"
[[ -n "$greeter" ]] || fail "theme.conf has no transitionColor"

# rgba(RRGGBBAA) - take the six colour digits, and insist it is fully opaque:
# a translucent clear colour shows the black underneath and defeats the point.
hypr_rgba="$(sed -n 's/.*background_color *= *"rgba(\([0-9a-fA-F]\{8\}\))".*/\1/p' "$HYPR" | head -1)"
[[ -n "$hypr_rgba" ]] || fail "colors.lua has no misc.background_color"
[[ "${hypr_rgba:6:2}" == "FF" || "${hypr_rgba:6:2}" == "ff" ]] \
    || fail "Hyprland's background_color is not opaque (alpha ${hypr_rgba:6:2})"
hypr="${hypr_rgba:0:6}"

shell="$(sed -n 's/^ *color: "#\([0-9a-fA-F]\{6\}\)"$/\1/p' "$BG" | head -1)"
[[ -n "$shell" ]] || fail "Background.qml has no literal curtain colour"

lower() { printf '%s' "$1" | tr 'A-F' 'a-f'; }
g="$(lower "$greeter")"; h="$(lower "$hypr")"; s="$(lower "$shell")"
[[ "$g" == "$h" ]] || fail "greeter #$g != Hyprland #$h"
[[ "$g" == "$s" ]] || fail "greeter #$g != shell curtain #$s"

# The greeter must fade the handoff layer in, not fade itself out - fading its
# own opacity goes to the compositor's black, which is the whole bug.
grep -q 'target: handoff; property: "opacity"; to: 1' "$GREETER" \
    || fail "greeter no longer fades to the handoff layer on login success"
grep -q 'target: root; property: "opacity"; to: 0' "$GREETER" \
    && fail "greeter is fading itself out to black again"

# The curtain is a full-screen opaque rectangle over the desktop background. If
# nothing can lift it, the desktop never appears at all.
grep -q 'onTriggered: bgRoot.wallpaperArrived = true' "$BG" \
    || fail "no timeout can lift the handoff curtain"

echo "ok"
