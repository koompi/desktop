#!/usr/bin/env bash
# koompi-wallpaper wrote its config through a fixed "$CONFIG_FILE.tmp", so two
# invocations shared one temp file. A pre-planted .tmp stands in for the other
# writer: the script must neither read it nor rename it away, and must leave no
# temp file of its own behind. Runs on a throwaway config, never the real one.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/dots/.local/bin/koompi-wallpaper"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/cfg" "$tmp/lib/static"
config="$tmp/cfg/config.json"

# Two "images": file(1) wants a whole PNG, so a 1x1 one.
for name in a b; do
    base64 -d > "$tmp/lib/static/$name.png" <<'PNG'
iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==
PNG
done
img="$(realpath "$tmp/lib/static/a.png")"

jq -n --arg lib "$tmp/lib" '{background: {workspaceWallpapers: {libraryPath: $lib}}}' > "$config"
printf 'OTHER WRITER\n' > "$config.tmp"

run_wallpaper() {
    KOOMPI_CONFIG_FILE="$config" KOOMPI_LOG_DIR="$tmp/logs" HOME="$tmp" \
        bash "$SCRIPT" "$@" > "$tmp/out" 2>&1
}

run_wallpaper set 1 "$img"
status=$?
(( status == 0 )) || fail "set exited $status: $(cat "$tmp/out")"
[[ "$(jq -r '.background.workspaceWallpapers.workspaces.ws1.path' "$config")" == "$img" ]] ||
    fail "ws1 path not written: $(jq -c . "$config")"
[[ "$(cat "$config.tmp")" == 'OTHER WRITER' ]] ||
    fail "the other writer's config.json.tmp was consumed or overwritten"

run_wallpaper mode 2 static
status=$?
(( status == 0 )) || fail "mode exited $status: $(cat "$tmp/out")"
[[ "$(jq -r '.background.workspaceWallpapers.workspaces.ws2.mode' "$config")" == static ]] ||
    fail "ws2 mode not written: $(jq -c . "$config")"

run_wallpaper seed
status=$?
(( status == 0 )) || fail "seed exited $status: $(cat "$tmp/out")"
[[ "$(jq '[.background.workspaceWallpapers.workspaces[] | select(.mode == "static")] | length' "$config")" -eq 10 ]] ||
    fail "seed did not fill all ten slots: $(jq -c . "$config")"

jq -e 'type == "object"' "$config" >/dev/null || fail "config.json is no longer valid JSON"
[[ "$(cat "$config.tmp")" == 'OTHER WRITER' ]] ||
    fail "the other writer's config.json.tmp was consumed or overwritten by a later command"
leftovers="$(find "$tmp/cfg" -name 'config.json.*' ! -name 'config.json.tmp')"
[[ -z "$leftovers" ]] || fail "temp files left beside the config: $leftovers"

printf 'wallpaper config write test passed\n'
