#!/usr/bin/env bash
# The cursor theme is stated in four places that cannot read each other, and
# when they drift the session shows two pointers: everything follows
# XCURSOR_THEME except an X11 client that names no theme, which follows
# ~/.icons/default and so gets whatever the installer wrote there. Telegram
# under XWayland is one of those clients, which is how the drift got noticed.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETUPS="$ROOT/sdata/install/setups/desktop.sh"
ENV_LUA="$ROOT/dots/.config/hypr/hyprland/env.lua"
EXECS_LUA="$ROOT/dots/.config/hypr/hyprland/execs.lua"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

want="$(grep -oP "^readonly KOOMPI_CURSOR_THEME='\K[^']+" "$SETUPS")"
want_size="$(grep -oP '^readonly KOOMPI_CURSOR_SIZE=\K.+' "$SETUPS")"
[[ -n "$want" && -n "$want_size" ]] || fail "setups.sh no longer declares the cursor theme and size"

env_theme="$(grep -oP 'hl\.env\("XCURSOR_THEME", "\K[^"]+' "$ENV_LUA")"
env_size="$(grep -oP 'hl\.env\("XCURSOR_SIZE", "\K[^"]+' "$ENV_LUA")"
[[ "$env_theme" == "$want" ]] \
    || fail "env.lua exports XCURSOR_THEME=$env_theme but the installer ships $want"
[[ "$env_size" == "$want_size" ]] \
    || fail "env.lua exports XCURSOR_SIZE=$env_size but the installer ships $want_size"

read -r exec_theme exec_size <<< "$(grep -oP 'hyprctl setcursor \K[[:alnum:]_-]+ [0-9]+' "$EXECS_LUA")"
[[ "$exec_theme" == "$want" ]] \
    || fail "execs.lua sets the compositor cursor to $exec_theme but the installer ships $want"
[[ "$exec_size" == "$want_size" ]] \
    || fail "execs.lua sets the cursor size to $exec_size but the installer ships $want_size"

# The fallback the installer writes is the one an X11 client with no theme of
# its own lands on, so it is the copy that has to agree, not just exist.
grep -q 'Inherits=\${KOOMPI_CURSOR_THEME}' "$SETUPS" \
    || fail "the ~/.icons/default fallback no longer derives from KOOMPI_CURSOR_THEME"

# Live check: the running session is a fifth statement of the same thing, and it
# is the one the user actually sees.
if [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]]; then
    live="$HOME/.icons/default/index.theme"
    if [[ -f "$live" ]]; then
        got="$(grep -oP '^Inherits=\K.+' "$live" || true)"
        [[ "$got" == "$want" ]] \
            || fail "this machine's X11 cursor fallback is $got, not $want; run ./setup install"
    fi
fi

echo "ok"
