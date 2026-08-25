#!/usr/bin/env bash
# koompi-stacking wrote hyprctl output to /tmp/.koompi-stacking-*.$$, a
# predictable name in a shared directory, and removed it only on success. Runs
# `clamp` with hyprctl stubbed and TMPDIR pointed at an empty directory: the
# placement must work, and nothing may be left behind on success or on failure.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/dots/.local/bin/koompi-stacking"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/scratch" "$tmp/run" "$tmp/state"

for cmd in bash python3 mktemp rm date mkdir wc grep cat; do
    path="$(command -v "$cmd")" || fail "test host has no $cmd"
    ln -s "$path" "$stub/$cmd"
done
cat > "$stub/hyprctl" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    monitors) echo '[{"id":0,"name":"eDP-1","x":0,"y":0,"width":1920,"height":1080,"scale":1.0,"reserved":[0,40,0,0]}]' ;;
    clients)  echo '[{"address":"0x1","mapped":true,"floating":true,"monitor":0,"at":[-50,-50],"size":[400,300]}]' ;;
    activewindow) exit 1 ;;
    dispatch) printf '%s\n' "$2" >> "${HYPRCTL_DISPATCH_LOG:?}" ;;
esac
STUB
chmod +x "$stub/hyprctl"

run_stacking() {
    env -i PATH="$stub" HOME="$tmp" TMPDIR="$tmp/scratch" \
        XDG_RUNTIME_DIR="$tmp/run" XDG_STATE_HOME="$tmp/state" \
        HYPRCTL_DISPATCH_LOG="$tmp/dispatch.log" \
        bash "$SCRIPT" "$@" > "$tmp/out" 2>&1
}

run_stacking clamp
status=$?
(( status == 0 )) || fail "clamp exited $status: $(cat "$tmp/out")"
grep -q '^1 window(s) pulled back' "$tmp/out" || fail "unexpected clamp output: $(cat "$tmp/out")"
grep -q 'hl.dsp.window.move' "$tmp/dispatch.log" || fail "the out-of-bounds window was never moved"
[[ -z "$(ls -A "$tmp/scratch")" ]] || fail "scratch files left behind after success: $(ls -A "$tmp/scratch")"
rm -f "$tmp/dispatch.log"

# maximize with hyprctl activewindow failing: set -e ends the script after the
# monitor snapshot was written. The trap must still clean up, and nothing may
# land in the shared /tmp (the old fixed names did, and stayed there).
shared_before="$(ls /tmp/.koompi-stacking-* 2>/dev/null)"
run_stacking maximize
status=$?
(( status != 0 )) || fail "maximize exited 0 although hyprctl activewindow failed"
[[ -f "$tmp/dispatch.log" ]] && fail "a window was moved although hyprctl activewindow failed"
[[ -z "$(ls -A "$tmp/scratch")" ]] || fail "scratch files left behind after failure: $(ls -A "$tmp/scratch")"
shared_after="$(ls /tmp/.koompi-stacking-* 2>/dev/null)"
[[ "$shared_after" == "$shared_before" ]] || fail "scratch files written to the shared /tmp: $shared_after"

printf 'stacking scratch test passed\n'
