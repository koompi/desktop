#!/usr/bin/env bash
# general.lua bound the touchscreen to a hard-coded "eDP-1". A desktop with a
# touchscreen has no eDP connector, and Hyprland logs an error at every reload
# for a bound output that does not exist. The config now reads the panel name
# from /sys/class/drm; this loads general.lua under plain lua with hl stubbed
# and io.popen answering with a chosen connector list.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
GENERAL="$REPO_ROOT/dots/.config/hypr/hyprland/general.lua"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

command -v lua >/dev/null 2>&1 || { printf 'lua not installed; skipping\n'; exit 0; }
[[ -f "$GENERAL" ]] || fail "missing $GENERAL"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/harness.lua" <<'LUA'
local function stub()
    return setmetatable({}, {__call = function() end, __index = function() return stub() end})
end
hl = stub()

local captured, seen = nil, false
hl.config = function(t)
    if t.input and t.input.touchdevice then
        seen = true
        captured = t.input.touchdevice.output
    end
end

-- The connector listing the config would get from `ls /sys/class/drm`.
local listing = os.getenv("FAKE_DRM") or ""
io.popen = function()
    local entries = {}
    for entry in listing:gmatch("%S+") do entries[#entries + 1] = entry end
    local i = 0
    return {
        lines = function() return function() i = i + 1; return entries[i] end end,
        close = function() return true end,
    }
end

dofile(arg[1])
if not seen then print("NO-TOUCHDEVICE-CONFIG") else print(captured or "<nil>") end
LUA

touch_output() { FAKE_DRM="$1" lua "$tmp/harness.lua" "$GENERAL" 2>&1; }

out="$(touch_output 'card0 card0-DP-1 card0-eDP-1 card0-HDMI-A-1 renderD128 version')"
[[ "$out" == 'eDP-1' ]] || fail "laptop with eDP-1: got '$out'"

out="$(touch_output 'card1 card1-eDP-2 card1-DP-3')"
[[ "$out" == 'eDP-2' ]] || fail "panel on a different connector index: got '$out', want eDP-2"

out="$(touch_output 'card0 card0-DP-1 card0-HDMI-A-1 renderD128 version')"
[[ "$out" == '<nil>' ]] || fail "desktop without an eDP panel must leave touchdevice.output unset, got '$out'"

printf 'touch output test passed\n'
