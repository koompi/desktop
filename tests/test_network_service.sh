#!/usr/bin/env bash
# Network.qml went from eleven nmcli forks to one koompi-shelld subscription. Its
# public surface had to survive that unchanged, because sixteen files bind to it and
# QML resolves a missing property to undefined rather than to an error: a dropped
# member shows up as a blank label or a dead button, never as a failed load.
#
# Read-only: greps the tree, talks to nothing.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
QS="$ROOT/dots/.config/quickshell/koompi"
QML="$QS/services/Network.qml"
AP="$QS/services/network/WifiAccessPoint.qml"
SHELLD="$ROOT/shell-services/shelld/src/services.rs"
PROTOCOL="$ROOT/shell-services/shelld/PROTOCOL.md"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$QML" ]] || fail "no Network.qml"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. No subprocess. Replacing eleven of them is the entire point of the port, and
#    one creeping back is how the shell ends up with two sources of truth.
grep -qE '^[[:space:]]*Process[[:space:]]*\{|"nmcli"' "$QML" \
    && fail "Network.qml spawns a process again; koompi-network is what reads NetworkManager now"

# 2. Everything the rest of the shell binds to still exists here. This is the check
#    that a rewrite of this file needs and QML cannot give.
grep -rhoE '\bNetwork\.[a-zA-Z_][a-zA-Z0-9_]*' "$QS/modules" "$QS/services" \
    --include='*.qml' 2> /dev/null \
    | sed 's/^Network\.//' | grep -vx 'qml' | sort -u > "$tmp/used"

sed -nE 's/.*\b(readonly )?property [a-zA-Z_<>.]+ ([a-zA-Z_][a-zA-Z0-9_]*).*/\2/p;
         s/.*\bfunction ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/p;
         s/.*\bsignal ([a-zA-Z_][a-zA-Z0-9_]*).*/\1/p' "$QML" | sort -u > "$tmp/declared"

[[ -s "$tmp/used" ]] || fail "found no Network.* references at all; this test stopped testing"
missing="$(comm -23 "$tmp/used" "$tmp/declared" | tr '\n' ' ')"
[[ -z "${missing// }" ]] \
    || fail "the shell binds to Network members this file no longer declares: $missing"

# 3. The access point objects the wifi lists render, same argument.
grep -rhoE '\b(accessPoint|network|modelData|ap)\.(ssid|bssid|strength|frequency|active|security|isSecure|askingPassword|path)\b' \
    "$QS/modules" --include='*.qml' 2> /dev/null \
    | sed 's/.*\.//' | sort -u > "$tmp/ap_used"
sed -nE 's/.*\b(readonly )?property [a-zA-Z_<>.]+ ([a-zA-Z_][a-zA-Z0-9_]*).*/\2/p' "$AP" | sort -u > "$tmp/ap_declared"
ap_missing="$(comm -23 "$tmp/ap_used" "$tmp/ap_declared" | tr '\n' ' ')"
[[ -z "${ap_missing// }" ]] \
    || fail "WifiAccessPoint no longer declares members the wifi lists read: $ap_missing"

# 4. Every command this file sends is one the daemon answers and the document names.
#    A typo on either side is silent: the daemon replies unknown_command and the QML
#    is not listening for it.
sed -nE 's/.*ShellServices\.command\("network", "([a-z_]+)".*/\1/p' "$QML" | sort -u > "$tmp/sent"
[[ -s "$tmp/sent" ]] || fail "Network.qml sends no commands at all"
[[ -f "$PROTOCOL" ]] || fail "no shelld/PROTOCOL.md"
while read -r cmd; do
    grep -q "\"$cmd\"" "$SHELLD" || fail "koompi-shelld does not answer the network command $cmd"
    grep -q "\`$cmd\`" "$PROTOCOL" || fail "the network command $cmd is not in PROTOCOL.md"
done < "$tmp/sent"

# 5. The ssid is `ay` on the wire and routinely not utf-8, so identity keys off the
#    bytes. Reconciling on the display string would merge two different networks.
grep -q 'ssidHex' "$QML" \
    || fail "Network.qml no longer keys access points on the raw ssid bytes"

echo "ok"
