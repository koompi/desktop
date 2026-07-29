#!/usr/bin/env bash

get_pictures_dir() {
    if command -v xdg-user-dir &> /dev/null; then
        xdg-user-dir PICTURES
        return
    fi

    local config_file="${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
    if [ -f "$config_file" ]; then
        local pictures_path
        # shellcheck source=/dev/null # user-dirs.dirs is generated at runtime, not in this repo
        pictures_path=$(source "$config_file" >/dev/null 2>&1; echo "$XDG_PICTURES_DIR")
        echo "${pictures_path/#\$HOME/$HOME}"
        return
    fi

    echo "$HOME/Pictures"
}

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
PICTURES_DIR=$(get_pictures_dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

mkdir -p "$PICTURES_DIR/Wallpapers"

illogicalImpulseConfigPath="$HOME/.config/koompi/config.json"
userAgent=$(jq -r '.networking.userAgent // empty' "$illogicalImpulseConfigPath" 2>/dev/null)

# osu! now puts this endpoint behind Cloudflare, so the response is often an
# HTML challenge rather than JSON. Bail out instead of handing switchwall.sh a
# path that was never downloaded - that leaves the desktop on a missing image.
response=$(curl -sA "$userAgent" "https://osu.ppy.sh/api/v2/seasonal-backgrounds")
images=$(echo "$response" | jq '.backgrounds | length' -r 2>/dev/null)
if ! [ "${images:-0}" -gt 0 ] 2>/dev/null; then
    echo "random_osu_wall: seasonal backgrounds unavailable (osu! API returned no JSON)" >&2
    exit 1
fi

randomIndex=$((RANDOM % images));
link=$(echo "$response" | jq ".backgrounds[$randomIndex].url" -r)
if [ -z "$link" ] || [ "$link" = "null" ]; then
    echo "random_osu_wall: no background url in response" >&2
    exit 1
fi

ext=$(echo "$link" | awk -F. '{print $NF}')
# With a target workspace, each workspace gets its own file: sharing one
# mutable filename meant a later download silently changed every workspace
# that pointed at it.
if [ -n "${KOOMPI_TARGET_WORKSPACE:-}" ]; then
    downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper-ws${KOOMPI_TARGET_WORKSPACE}.$ext"
else
    downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper.$ext"
fi
currentWallpaperPath=$(jq -r '.background.wallpaperPath' "$illogicalImpulseConfigPath")
if [ "$downloadPath" == "$currentWallpaperPath" ]; then
    downloadPath="$PICTURES_DIR/Wallpapers/random_wallpaper-1.$ext"
fi
if ! curl -fsA "$userAgent" "$link" -o "$downloadPath" || [ ! -s "$downloadPath" ]; then
    echo "random_osu_wall: download failed for $link" >&2
    rm -f "$downloadPath"
    exit 1
fi
"$SCRIPT_DIR/../apply_wall.sh" "$downloadPath"
