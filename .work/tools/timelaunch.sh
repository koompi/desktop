#!/usr/bin/env bash
# Time from launch to first mapped window, by window class (case-insensitive substring).
#   .work/tools/timelaunch.sh <class-substring> <label> <command...>
# Kills only the window it timed (by the pid Hyprland reports), never by name.
set -uo pipefail
cls=$1; label=$2; shift 2
if hyprctl clients -j | grep -qi "\"class\": \"[^\"]*$cls"; then
    echo "$label: a '$cls' window is already open; close it first" >&2; exit 2
fi
s=$(date +%s.%N)
"$@" >"/tmp/timelaunch-$label.log" 2>&1
for _ in $(seq 1 600); do
    hyprctl clients -j | grep -qi "\"class\": \"[^\"]*$cls" && break
    sleep 0.1
done
e=$(date +%s.%N)
pid=$(hyprctl clients -j | jq -r --arg c "$cls" '.[] | select(.class | ascii_downcase | contains($c | ascii_downcase)) | .pid' | head -1)
xw=$(hyprctl clients -j | jq -r --arg c "$cls" '.[] | select(.class | ascii_downcase | contains($c | ascii_downcase)) | .xwayland' | head -1)
if [[ -z "$pid" ]]; then printf '%s: no window within 60s (TIMEOUT)\n' "$label"; exit 1; fi
printf '%s: %.2fs (xwayland=%s, pid=%s)\n' "$label" "$(echo "$e - $s" | bc)" "$xw" "$pid"
sleep 1; kill "$pid" 2>/dev/null; sleep 1
