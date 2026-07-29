#!/usr/bin/env bash

# Combined random source, bound to Ctrl+Super+Alt+T. Picks one of the enabled
# sources at random so the keybind draws from every source at once instead of
# just one. Override the set in config.json:
#   .background.randomWallpaper.sources   e.g. ["library", "konachan"]
# Online sources fall back to the offline library when the network is down.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$XDG_CONFIG_HOME/koompi/config.json"

sources=()
while IFS= read -r s; do
    # A source name is only ever a script beside this one; anything else in
    # config.json is ignored rather than executed.
    [ -x "$SCRIPT_DIR/random_${s}_wall.sh" ] && sources+=("$s")
done < <(jq -r '.background.randomWallpaper.sources[]?' "$CONFIG_FILE" 2>/dev/null)

# Konachan is the same source the weeb policy hides in Settings, so the keybind
# must not sneak it in when that policy is off. osu! seasonal is out of the
# default set: its API sits behind a Cloudflare challenge (dead upstream); the
# script stays for explicit config.json opt-in should it recover.
if [ "${#sources[@]}" -eq 0 ]; then
    sources=(library)
    if [ "$(jq -r '.policies.weeb // 0' "$CONFIG_FILE" 2>/dev/null)" = "1" ]; then
        sources+=(konachan)
    fi
fi

# Pin the target workspace, so a source that spends seconds downloading still
# lands on the workspace the key was pressed on. The shell passes the id as $1
# because it knows the focused workspace instantly; falling back to hyprctl here
# would already be a subprocess too late.
if [ -n "${1:-}" ] && [ "$1" != "0" ]; then
    KOOMPI_TARGET_WORKSPACE="$1"
    export KOOMPI_TARGET_WORKSPACE
fi

# Walk the sources in random order rather than betting the keypress on one of
# them. Any source can be unavailable: no library installed yet, an API behind
# Cloudflare, no network. Giving up after the first pick makes the keybind
# silently do nothing, which reads as a broken key.
while [ "${#sources[@]}" -gt 0 ]; do
    idx=$((RANDOM % ${#sources[@]}))
    pick="${sources[idx]}"
    if "$SCRIPT_DIR/random_${pick}_wall.sh"; then
        exit 0
    fi
    echo "random_wall: source '$pick' produced nothing, trying another" >&2
    unset 'sources[idx]'
    sources=("${sources[@]}")
done

echo "random_wall: no source could provide a wallpaper" >&2
exit 1
