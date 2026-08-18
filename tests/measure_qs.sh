#!/usr/bin/env bash
# One-shot resource snapshot of the running Quickshell process, for A/B measurement
# during performance work. Not part of ./tests/run.sh: it needs a live seat (a
# running `qs` and, optionally, `gputop`), which the rest of the suite deliberately
# never touches. Run it by hand: ./tests/measure_qs.sh [label]
#
# Discards nothing itself - it is one sample, not a settling run. Take several,
# spaced out, and say what else was running on the machine at the time; a sample
# taken while the seat is busy is not comparable to one taken quiet.
set -uo pipefail

label="${1:-}"
pid="$(pgrep -x qs | head -1)"
if [[ -z "$pid" ]]; then
    echo "no running 'qs' process found" >&2
    exit 1
fi

ts="$(date -Iseconds)"
echo "=== qs measurement ${label:+($label) }at $ts, pid $pid ==="

echo "--- memory (smaps_rollup) ---"
if [[ -r "/proc/$pid/smaps_rollup" ]]; then
    grep -E '^(Rss|Pss|Swap|Anonymous):' "/proc/$pid/smaps_rollup"
else
    echo "smaps_rollup unreadable"
fi
grep -E '^(VmHWM|Threads):' "/proc/$pid/status" 2>/dev/null

echo "--- CPU (10s settle sample) ---"
read -r u1 s1 < <(awk '{print $14, $15}' "/proc/$pid/stat" 2>/dev/null)
sleep 10
read -r u2 s2 < <(awk '{print $14, $15}' "/proc/$pid/stat" 2>/dev/null)
hz="$(getconf CLK_TCK)"
awk -v u1="$u1" -v s1="$s1" -v u2="$u2" -v s2="$s2" -v hz="$hz" \
    'BEGIN { pct = (((u2-u1)+(s2-s1))/hz) / 10 * 100; printf "%.2f%% of one core\n", pct }'
awk '{print "load average: " $0}' /proc/loadavg 2>/dev/null

echo "--- layers (mapped surfaces) ---"
if command -v hyprctl >/dev/null; then
    hyprctl layers 2>/dev/null | grep -c "pid: $pid" | awk '{print $1 " quickshell layer(s) mapped"}'
else
    echo "hyprctl not found"
fi

echo "--- GPU (gputop, one refresh) ---"
if command -v gputop >/dev/null; then
    line="$(timeout 3 gputop 2>/dev/null | grep -E "^ *$pid " | tail -1)"
    [[ -n "$line" ]] && echo "$line" || echo "qs not seen in a gputop refresh (0% engine use is common)"
else
    echo "gputop not found"
fi
