#!/usr/bin/env bash
# The repo is now koompi/koompi-hd (previously just "desktop"), and the managed
# checkout's default directory moved with it (~/.local/share/koompi-desktop ->
# ~/.local/share/koompi-hd). resolve_checkout must still find an existing
# checkout under any old name when the state file is missing or stale: getting
# this wrong silently clones a second desktop over the first on every machine.
# Pins: every old name stays guessable, the new name is guessed too, the state
# file beats every guess, and a found old-name checkout is never re-cloned.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$ROOT/dots/.local/share/koompi/libexec/update"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# Run resolve_checkout the way the installed script computes its own defaults:
# fresh environment, real script, library guard so main never runs.
resolve() { # $1 = fake HOME, $2 = state-file path to record ("" = none)
    HOME="$1" XDG_DATA_HOME="$1/.local/share" XDG_STATE_HOME="$1/.local/state" \
    KOOMPI_UPDATE_LIBRARY=1 NO_COLOR=1 bash -c '
        source "$0"
        if [[ -n "${1:-}" ]]; then
            mkdir -p "$(dirname -- "$REPO_PATH_FILE")"
            printf "%s\n" "$1" > "$REPO_PATH_FILE"
        fi
        resolve_checkout' "$UPDATE" "${2:-}"
}

mkcheckout() { mkdir -p "$1"; : > "$1/setup"; chmod +x "$1/setup"; }

# --- 1. install from before the rename, no state file: the old default dir ---
h="$T/pre-rename"
mkcheckout "$h/.local/share/koompi-desktop"
out="$(resolve "$h")" || fail "old-default checkout was not found at all"
[[ "$out" == "$h/.local/share/koompi-desktop" ]] \
    || fail "expected the pre-rename checkout, got: $out"
[[ ! -e "$h/.local/share/koompi-hd" ]] \
    || fail "a second checkout was cloned over the existing one"

# --- 2. same, but the checkout sits under a legacy bare-home name ------------
h="$T/bare-legacy"
mkcheckout "$h/koompi-desktop"
out="$(resolve "$h")" || fail "bare legacy checkout was not found"
[[ "$out" == "$h/koompi-desktop" ]] \
    || fail "expected ~/koompi-desktop, got: $out"

# --- 3. a checkout cloned after the rename -----------------------------------
h="$T/post-rename"
mkcheckout "$h/.local/share/koompi-hd"
out="$(resolve "$h")" || fail "koompi-hd checkout was not found"
[[ "$out" == "$h/.local/share/koompi-hd" ]] \
    || fail "expected ~/.local/share/koompi-hd, got: $out"

# --- 4. both names on disk: the current name wins ----------------------------
h="$T/both"
mkcheckout "$h/.local/share/koompi-desktop"
mkcheckout "$h/.local/share/koompi-hd"
out="$(resolve "$h")" || fail "no checkout found though both exist"
[[ "$out" == "$h/.local/share/koompi-hd" ]] \
    || fail "current-name checkout should be preferred, got: $out"

# --- 5. the state file beats every guess -------------------------------------
h="$T/state-wins"
mkcheckout "$h/myrepo"
mkcheckout "$h/.local/share/koompi-desktop"
out="$(resolve "$h" "$h/myrepo")" || fail "state-file checkout was not found"
[[ "$out" == "$h/myrepo" ]] \
    || fail "the recorded state-file path must win over the guesses, got: $out"

echo "ok: resolve_checkout still finds pre-rename checkouts and never re-clones one"
