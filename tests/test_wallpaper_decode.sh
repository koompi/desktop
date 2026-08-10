#!/usr/bin/env bash
# The wallpaper is drawn by two crossfade cells. Decoding each at the file's
# native resolution costs 42.3 MB of anon on a 1920x1200 screen against 20.8 with
# a cap, and the cap is easy to lose again: the original code left sourceSize off
# on purpose, because binding it re-decodes a few frames into a switch when the
# magick zoom probe lands and corrects the scale. Dropping opacity on that
# re-decode is the dark blink, so the cap only holds if the opacity condition
# remembers the source already shown. Both cells need both halves.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BG="$ROOT/dots/.config/quickshell/koompi/modules/koompi/background/Background.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$BG" ]] || fail "Background.qml is missing"

cells=$(grep -c 'id: cell[AB]Image' "$BG")
[[ $cells -eq 2 ]] || fail "expected two crossfade cells, found $cells"

want() {
    local n pattern=$1 what=$2
    n=$(grep -c -- "$pattern" "$BG" || true)
    [[ $n -eq 2 ]] || fail "$what: $n of 2 cells"
}

want 'sourceSize.width:' "a cell decodes at the file's native resolution again; cap sourceSize"
want 'sourceSize.height:' "a cell caps only one axis, which leaves the decode uncapped"
want 'source === readySource' "a cell drops opacity while re-decoding a source it already shows"
want 'readySource = source' "a cell never records the source it managed to show"

echo "ok"
