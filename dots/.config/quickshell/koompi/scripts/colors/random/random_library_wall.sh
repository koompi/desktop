#!/usr/bin/env bash

# Random wallpaper from the KOOMPI library. This is the default random source:
# it ships with the OS, works offline, and needs no content filtering. The
# online sources (konachan, osu) stay available as explicit choices.

XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$XDG_CONFIG_HOME/koompi/config.json"

get_pictures_dir() {
    if command -v xdg-user-dir >/dev/null 2>&1; then
        xdg-user-dir PICTURES
        return
    fi
    echo "$HOME/Pictures"
}

# Two homes, on purpose. The shipped set is installed read-only by the
# koompi-branding package so it survives, upgrades, and costs one copy for the
# whole machine. The user's own folder is where anything they add lives, and
# where the online sources save what they download.
dirs=()
configured=$(jq -r '.background.workspaceWallpapers.libraryPath // empty' "$CONFIG_FILE" 2>/dev/null)
[ -n "$configured" ] && [ -d "$configured" ] && dirs+=("$configured")
[ -d "/usr/share/backgrounds/koompi" ] && dirs+=("/usr/share/backgrounds/koompi")
user_dir="$(get_pictures_dir)/Wallpapers"
[ -d "$user_dir" ] && dirs+=("$user_dir")

if [ "${#dirs[@]}" -eq 0 ]; then
    echo "random_library_wall: no wallpaper directory found" >&2
    exit 1
fi

# Curation notes and source manifests sit beside the images, and
# not-desktop-grade/ holds ones held back from the shipped set. Select on mime
# type rather than extension: several library images have no extension.
images=()
while IFS= read -r -d '' f; do
    case "$(file -b --mime-type "$f")" in
        image/*) images+=("$f") ;;
    esac
done < <(find "${dirs[@]}" -type f -not -path '*/not-desktop-grade/*' -print0)

if [ "${#images[@]}" -eq 0 ]; then
    echo "random_library_wall: no images in ${dirs[*]}" >&2
    exit 1
fi

# Keep every workspace's wallpaper distinct: exclude images already used by
# any workspace or as the global wallpaper. When the pool is smaller than the
# number of workspaces the filter empties out; fall back to the full pool then,
# since a repeat beats a dead keypress.
mapfile -t used < <(jq -r '
    [.background.wallpaperPath // empty]
    + [.background.workspaceWallpapers.workspaces[]?.path // empty]
    | .[] | select(length > 0)' "$CONFIG_FILE" 2>/dev/null)
if [ "${#used[@]}" -gt 0 ]; then
    fresh=()
    for img in "${images[@]}"; do
        keep=1
        for u in "${used[@]}"; do
            [ "$img" = "$u" ] && { keep=0; break; }
        done
        [ "$keep" = 1 ] && fresh+=("$img")
    done
    [ "${#fresh[@]}" -gt 0 ] && images=("${fresh[@]}")
fi

pick="${images[RANDOM % ${#images[@]}]}"

# --print just names a wallpaper without touching anything. The lock screen uses
# it to show a different image each time it locks.
if [ "${1:-}" = "--print" ]; then
    printf '%s\n' "$pick"
    exit 0
fi

"$SCRIPT_DIR/../apply_wall.sh" "$pick"
