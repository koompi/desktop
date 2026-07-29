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

# Content filter for online anime wallpapers. Konachan's own "rating:safe"
# still allows suggestive art, so KOOMPI defaults to safe, character-free
# images (no_humans -> scenery/objects, nothing sexy). Override in config.json:
#   .background.randomWallpaper.konachanTags   e.g. "rating:safe -bikini -swimsuit"
tags=$(jq -r '.background.randomWallpaper.konachanTags // empty' "$illogicalImpulseConfigPath" 2>/dev/null)
[ -z "$tags" ] && tags="rating:safe no_humans"
encodedTags=$(jq -rn --arg t "$tags" '$t|@uri')

# Fetch a page of matches and pick one at random. Retry across pages so a
# stricter filter (fewer posts) does not land on an empty page and fail.
link="null"
for _ in 1 2 3 4 5; do
    page=$((1 + RANDOM % 50))
    response=$(curl -sA "$userAgent" "https://konachan.net/post.json?tags=${encodedTags}&limit=40&page=$page")
    count=$(echo "$response" | jq 'length' 2>/dev/null || echo 0)
    if [ "${count:-0}" -gt 0 ]; then
        idx=$((RANDOM % count))
        link=$(echo "$response" | jq -r ".[$idx].file_url")
        [ "$link" != "null" ] && [ -n "$link" ] && break
    fi
done

if [ "$link" = "null" ] || [ -z "$link" ]; then
    echo "random_konachan_wall: no image found for tags '$tags'" >&2
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
    echo "random_konachan_wall: download failed for $link" >&2
    rm -f "$downloadPath"
    exit 1
fi
"$SCRIPT_DIR/../apply_wall.sh" "$downloadPath"
