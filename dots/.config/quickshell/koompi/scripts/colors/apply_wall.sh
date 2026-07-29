#!/usr/bin/env bash

# Single apply step for every random wallpaper source.
#
# With workspace wallpapers on, a picked image lands on the ACTIVE workspace only
# and the theme is left alone: matugen colors are global, so regenerating them
# would leak one workspace's wallpaper into every other workspace's UI. With the
# feature off, this is the old behavior, global wallpaper plus theme regen.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$XDG_CONFIG_HOME/koompi/config.json"
WALLPAPER_CMD="$XDG_CONFIG_HOME/hypr/custom/scripts/koompi-wallpaper.sh"

image="${1:-}"
[ -n "$image" ] || { echo "apply_wall: image path required" >&2; exit 1; }
shift
# Anything after the image is for switchwall.sh, e.g. --mode dark. A
# per-workspace set ignores it, since it does no theming by design.
switchwall_args=("$@")

enabled=$(jq -r '.background.workspaceWallpapers.enabled // false' "$CONFIG_FILE" 2>/dev/null)
if [ "$enabled" = "true" ] && [ -x "$WALLPAPER_CMD" ]; then
    # KOOMPI_TARGET_WORKSPACE is captured by the caller the moment the keybind
    # fires. An online source can spend seconds downloading, and focus may have
    # moved on by the time it finishes, so trust the caller over live state.
    if [ -n "${KOOMPI_TARGET_WORKSPACE:-}" ]; then
        exec "$WALLPAPER_CMD" set "$KOOMPI_TARGET_WORKSPACE" "$image"
    fi
    exec "$WALLPAPER_CMD" set-active "$image"
fi

exec "$SCRIPT_DIR/switchwall.sh" "${switchwall_args[@]}" --image "$image"
