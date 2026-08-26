#!/usr/bin/env bash
# The repo was renamed twice on 2026-08-26 (desktop, then the one-day
# koompi-hd spelling, then koompi-desktop). The managed checkout's default
# directory went with it (~/.local/share/koompi-desktop -> ~/.local/share/
# koompi-hd -> back to ~/.local/share/koompi-desktop), so a machine can carry
# a checkout under any of these names depending on when it last updated.
# resolve_checkout must find an existing checkout under every name when the
# state file is missing or stale: getting this wrong silently clones a second
# desktop over the first on every machine. Pins: every generation stays
# guessable, the current name is guessed first and wins when two exist, and
# the state file beats every guess.
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

# --- 1. a checkout under the default dir, no state file: found, not re-cloned -
h="$T/default-dir"
mkcheckout "$h/.local/share/koompi-desktop"
out="$(resolve "$h")" || fail "default-dir checkout was not found at all"
[[ "$out" == "$h/.local/share/koompi-desktop" ]] \
    || fail "expected the default-dir checkout, got: $out"
[[ ! -e "$h/.local/share/koompi-hd" ]] \
    || fail "a second checkout was cloned over the existing one"

# --- 2. a koompi-hd checkout from the one-day window: found, not re-cloned ----
h="$T/hd-window"
mkcheckout "$h/.local/share/koompi-hd"
out="$(resolve "$h")" || fail "koompi-hd checkout was not found"
[[ "$out" == "$h/.local/share/koompi-hd" ]] \
    || fail "expected the koompi-hd checkout, got: $out"
[[ ! -e "$h/.local/share/koompi-desktop" ]] \
    || fail "a second checkout was cloned over the koompi-hd one"

# --- 3. both generations on disk: the current name wins ------------------------
h="$T/both"
mkcheckout "$h/.local/share/koompi-hd"
mkcheckout "$h/.local/share/koompi-desktop"
out="$(resolve "$h")" || fail "no checkout found though both exist"
[[ "$out" == "$h/.local/share/koompi-desktop" ]] \
    || fail "current-name checkout should be preferred over koompi-hd, got: $out"

# --- 4. a bare-home checkout under an older generation's name ------------------
h="$T/bare-legacy"
mkcheckout "$h/koompi-hyprland"
out="$(resolve "$h")" || fail "bare legacy checkout was not found"
[[ "$out" == "$h/koompi-hyprland" ]] \
    || fail "expected ~/koompi-hyprland, got: $out"

# --- 5. the state file beats every guess ---------------------------------------
h="$T/state-wins"
mkcheckout "$h/myrepo"
mkcheckout "$h/.local/share/koompi-desktop"
out="$(resolve "$h" "$h/myrepo")" || fail "state-file checkout was not found"
[[ "$out" == "$h/myrepo" ]] \
    || fail "the recorded state-file path must win over the guesses, got: $out"

echo "ok: resolve_checkout finds checkouts under every name the repo has had"
