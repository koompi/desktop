#!/usr/bin/env bash
# koompi-displays validated its generated monitors.lua with luac or lua, and no
# koompi package depends on either: on a minimal system every placement ended
# "failed lua validation, not persisted" and the layout was lost at login.
# Runs the script with hyprctl stubbed and no lua on PATH, then again with a
# failing luac to show validation still gates when an interpreter exists.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/dots/.local/bin/koompi-displays"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/config/hypr"

# PATH is the stub dir alone: no lua, no luac, and hyprctl never reaches the session.
for cmd in bash jq date mktemp mv rm sleep cat; do
    path="$(command -v "$cmd")" || fail "test host has no $cmd"
    ln -s "$path" "$stub/$cmd"
done
cat > "$stub/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    monitors) echo '[{"name":"eDP-1","width":1920,"height":1080,"refreshRate":60.0,"scale":1.0,"x":0,"y":0},{"name":"HDMI-A-1","width":2560,"height":1440,"refreshRate":59.95,"scale":1.0,"x":1920,"y":0}]' ;;
    eval)     printf '%s\n' "$2" >> "${HYPRCTL_EVAL_LOG:?}" ;;
esac
STUB
chmod +x "$stub/hyprctl"

run_displays() {
    env -i PATH="$stub" HOME="$tmp" XDG_CONFIG_HOME="$tmp/config" HYPRCTL_EVAL_LOG="$tmp/eval.log" \
        bash "$SCRIPT" "$@" > "$tmp/out" 2>&1
}

monitors_lua="$tmp/config/hypr/monitors.lua"

run_displays place HDMI-A-1 right
status=$?
(( status == 0 )) || fail "place exited $status with no lua interpreter: $(cat "$tmp/out")"
[[ -f "$monitors_lua" ]] || fail "monitors.lua was not persisted without a lua interpreter"
grep -q 'output = "HDMI-A-1"' "$monitors_lua" || fail "monitors.lua does not describe HDMI-A-1: $(cat "$monitors_lua")"
grep -q 'output = "eDP-1"' "$monitors_lua" || fail "monitors.lua does not describe eDP-1: $(cat "$monitors_lua")"
[[ "$(grep -c '^hl.monitor' "$tmp/eval.log")" -eq 2 ]] || fail "expected two hl.monitor hot-applies, got: $(cat "$tmp/eval.log")"

# The unvalidated file must still be lua: check it with the real luac when the
# test host has one.
if command -v luac >/dev/null 2>&1; then
    luac -p "$monitors_lua" || fail "the generated monitors.lua is not valid lua: $(cat "$monitors_lua")"
fi

# With an interpreter present, its verdict still decides.
printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/luac"
chmod +x "$stub/luac"
cp "$monitors_lua" "$tmp/before.lua"
run_displays place HDMI-A-1 left
status=$?
(( status != 0 )) || fail "place exited 0 although luac rejected the file"
grep -q 'failed lua validation' "$tmp/out" || fail "a rejected file was not reported: $(cat "$tmp/out")"
cmp -s "$monitors_lua" "$tmp/before.lua" || fail "a file luac rejected was persisted anyway"

printf 'displays persist test passed\n'
