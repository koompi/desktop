#!/usr/bin/env bash
# The global menu has two implementations answering one stdio protocol, so the
# conformance suite is the contract between them rather than a test of either.
# scripts/global-menu/tests/test_daemon.py takes GLOBAL_MENU_DAEMON and drives
# whichever binary it names against real applications on a real session bus.
#
# Neither toolchain is required. A machine with no cargo still has the zig
# daemon, and a machine with neither built has nothing to prove, which matches
# how setups.sh treats both: the feature degrades, the install does not fail.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SUITE="$ROOT/dots/.config/quickshell/koompi/scripts/global-menu/tests/test_daemon.py"
ZIG_BIN="$ROOT/dots/.config/quickshell/koompi/scripts/global-menu/zig-out/bin/global-menu-daemon"
RUST_BIN="$ROOT/globalmenu/target/release/global-menu-daemon"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
skip() { printf 'skip: %s\n' "$1"; }

[[ -f "$SUITE" ]] || fail "the conformance suite is missing"

# The suite has to be able to run either binary, or it only ever tests the one
# it was written against and the port is unverified by construction.
grep -q 'GLOBAL_MENU_DAEMON' "$SUITE" \
    || fail "test_daemon.py no longer takes GLOBAL_MENU_DAEMON, so it can only test one implementation"

command -v python3 > /dev/null || { skip "no python3; cannot run the conformance suite"; exit 0; }
command -v dbus-run-session > /dev/null || { skip "no dbus-run-session; the suite needs a session bus"; exit 0; }

ran=0

run_suite() {
    local name=$1 bin=$2
    [[ -x "$bin" ]] || { skip "$name daemon is not built"; return 0; }
    printf -- '--- %s\n' "$name"
    GLOBAL_MENU_DAEMON="$bin" timeout 300 python3 "$SUITE" > "$tmp/$name.log" 2>&1
    local rc=$?
    tail -3 "$tmp/$name.log"
    [[ $rc -eq 0 ]] || fail "$name daemon failed the conformance suite; see $tmp/$name.log"
    ran=$((ran + 1))
}

# The shell reads one payload before it sends anything, so a daemon that
# resolves nothing at startup still has to say so, or the bar sits on an empty
# menu with no retry scheduled until the user next changes focus. The
# conformance suite cannot see this: --test bypasses the focus guard that
# swallows the payload, so it only shows up against a live compositor.
opens_empty() {
    local name=$1 bin=$2
    [[ -x "$bin" ]] || return 0
    [[ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]] \
        || { skip "no compositor; cannot check the $name startup payload"; return 0; }
    printf -- '--- %s startup payload\n' "$name"
    local got
    got=$(dbus-run-session -- sh -c "sleep 5 | timeout 5 '$bin' 2> /dev/null | head -n 1")
    [[ $got == '{"items":[],"gen":1}' ]] \
        || fail "$name daemon opened with '$got', not the empty payload the shell waits for"
    ran=$((ran + 1))
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

run_suite zig "$ZIG_BIN"
run_suite rust "$RUST_BIN"

opens_empty zig "$ZIG_BIN"
opens_empty rust "$RUST_BIN"

if command -v cargo > /dev/null && [[ -f "$ROOT/globalmenu/Cargo.toml" ]]; then
    printf -- '--- cargo test\n'
    ( cd "$ROOT/globalmenu" && cargo test --quiet ) || fail "globalmenu unit tests failed"
    ran=$((ran + 1))
fi

[[ $ran -gt 0 ]] || skip "nothing was built, so nothing was checked"
echo "ok"
