#!/usr/bin/env bash
# HyprlandData.qml went from six respawned `hyprctl -j` processes per event to one
# koompi-shelld subscription. Fourteen files bind to its properties and QML resolves a
# missing one to undefined rather than to an error, so a dropped member is a blank
# label or an empty overview, never a failed load. Same for a mistyped key on the wire.
#
# Read-only: greps the tree, talks to nothing.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$ROOT/dots/.config/quickshell/koompi"
QML="$QS/services/HyprlandData.qml"
WIRE="$ROOT/shell-services/shelld/src/wire.rs"
PROTOCOL="$ROOT/shell-services/shelld/PROTOCOL.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$QML" ]] || fail "no HyprlandData.qml"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. No subprocess. Six of them per debounced event is what the port removed.
grep -qE '^[[:space:]]*Process[[:space:]]*\{|"hyprctl"' "$QML" \
    && fail "HyprlandData.qml spawns a process again; koompi-hyprland is what reads the compositor now"

# 2. Everything the rest of the shell binds to still exists here.
grep -rhoE '\bHyprlandData\.[a-zA-Z_][a-zA-Z0-9_]*' "$QS/modules" "$QS/services" \
    --include='*.qml' 2> /dev/null \
    | sed 's/^HyprlandData\.//' | sort -u > "$tmp/used"

sed -nE 's/.*\b(readonly )?property [a-zA-Z_<>.]+ ([a-zA-Z_][a-zA-Z0-9_]*).*/\2/p;
         s/.*\bfunction ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/p' "$QML" | sort -u > "$tmp/declared"

[[ -s "$tmp/used" ]] || fail "found no HyprlandData.* references at all; this test stopped testing"
missing="$(comm -23 "$tmp/used" "$tmp/declared" | tr '\n' ' ')"
[[ -z "${missing// }" ]] \
    || fail "the shell binds to HyprlandData members this file no longer declares: $missing"

# 3. Every key this file reads off the wire is one the daemon writes and the document
#    names. `state?.numbered_workspaces` would read undefined and empty the bar in
#    silence; nothing in QML or Rust would say a word.
sed -nE 's/.*state\?\.([a-z_]+).*/\1/p' "$QML" | sort -u > "$tmp/keys"
[[ -s "$tmp/keys" ]] || fail "HyprlandData.qml reads nothing off the daemon's state"
while read -r key; do
    grep -q "\"$key\"" "$WIRE" || fail "koompi-shelld does not put $key in the hyprland state"
    grep -q "\`$key\`" "$PROTOCOL" || fail "the hyprland state field $key is not in PROTOCOL.md"
done < "$tmp/keys"

# 4. The objects are the compositor's own JSON, so the consumers keep reading hyprctl's
#    field names. A snake_case rename in the crate would land here as undefined.
grep -q 'initialClass' "$ROOT/shell-services/hyprland/src/model.rs" \
    || fail "the client model no longer carries hyprctl's own field names"
grep -q 'Serialize' "$ROOT/shell-services/hyprland/src/model.rs" \
    || fail "the hyprland model no longer serialises, so nothing can put it on the wire"

echo "ok"
