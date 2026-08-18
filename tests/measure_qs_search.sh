#!/usr/bin/env bash
# One-shot resource snapshot of the running Quickshell process, for A/B
# measurement of search work specifically (before/after a scoring change,
# under different dataset sizes, etc). Extends tests/measure_qs.sh's shape —
# same pgrep -x qs, smaps_rollup, /proc/$pid/status, CPU%-over-a-settle-
# window, hyprctl layers, one gputop refresh — with a --label to say what
# machine state this snapshot was taken in, and --before/--after to diff two
# prior snapshots. Not part of ./tests/run.sh: it needs a live seat, same as
# measure_qs.sh, and this file doesn't import that one — they're independent
# tools, per J01/J02 being independent benches.
#
# This script does not put the machine into cold/steady/stress state itself,
# and does not drive any search queries itself (see SearchBench.qml's
# runQuery IPC call for that) — it takes one snapshot of whatever state `qs`
# is already in when you run it. --label only controls the header text
# printed; the caller is responsible for actually reproducing that state
# (e.g. run a batch of SearchBench.runQuery calls, or leave it idle) before
# invoking this script. Discards nothing itself - it is one sample, not a
# settling run.
#
# --before/--after diff format: this script's own snapshot output is the
# diff format (same shape as measure_qs.sh, so a file saved from either
# script works on either side of --before/--after). Fields are pulled back
# out of that text with grep/awk rather than a second structured format, so
# there is exactly one output shape to read, by eye or by script.
#
# Usage:
#   ./tests/measure_qs_search.sh [--label cold|steady|stress]
#   ./tests/measure_qs_search.sh --before FILE --after FILE
set -uo pipefail

label=""
before_file=""
after_file=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --label) label="${2:-}"; shift 2 ;;
        --before) before_file="${2:-}"; shift 2 ;;
        --after) after_file="${2:-}"; shift 2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
done

# Pull one metric's numeric value out of a saved snapshot file. label is the
# exact text preceding the number (e.g. "Rss:", "Threads:", "of one core").
extract() {
    local file="$1" label="$2"
    grep -oE "${label}[[:space:]]*[0-9]+(\.[0-9]+)?" "$file" 2>/dev/null \
        | head -1 | grep -oE '[0-9]+(\.[0-9]+)?'
}

if [[ -n "$before_file" || -n "$after_file" ]]; then
    if [[ -z "$before_file" || -z "$after_file" ]]; then
        echo "--before and --after must be given together" >&2
        exit 2
    fi
    for f in "$before_file" "$after_file"; do
        [[ -r "$f" ]] || { echo "cannot read $f" >&2; exit 1; }
    done

    echo "=== delta: $before_file -> $after_file ==="
    printf '%-12s %12s %12s %12s\n' "metric" "before" "after" "delta"
    for metric_label in "Rss:" "Pss:" "Swap:" "Anonymous:" "VmHWM:" "Threads:"; do
        b="$(extract "$before_file" "$metric_label")"
        a="$(extract "$after_file" "$metric_label")"
        name="${metric_label%:}"
        if [[ -n "$b" && -n "$a" ]]; then
            printf '%-12s %12s %12s %12s\n' "$name" "$b" "$a" "$(awk -v b="$b" -v a="$a" 'BEGIN { printf "%+d", a - b }')"
        else
            printf '%-12s %12s %12s %12s\n' "$name" "${b:-?}" "${a:-?}" "n/a"
        fi
    done
    b_cpu="$(grep -oE '[0-9]+\.[0-9]+% of one core' "$before_file" 2>/dev/null | head -1 | grep -oE '^[0-9]+\.[0-9]+')"
    a_cpu="$(grep -oE '[0-9]+\.[0-9]+% of one core' "$after_file" 2>/dev/null | head -1 | grep -oE '^[0-9]+\.[0-9]+')"
    if [[ -n "$b_cpu" && -n "$a_cpu" ]]; then
        printf '%-12s %11s%% %11s%% %+11.2f%%\n' "CPU" "$b_cpu" "$a_cpu" "$(awk -v b="$b_cpu" -v a="$a_cpu" 'BEGIN { print a - b }')"
    else
        printf '%-12s %12s %12s %12s\n' "CPU" "${b_cpu:-?}%" "${a_cpu:-?}%" "n/a"
    fi
    exit 0
fi

pid="$(pgrep -x qs | head -1)"
if [[ -z "$pid" ]]; then
    echo "no running 'qs' process found" >&2
    exit 1
fi

ts="$(date -Iseconds)"
echo "=== qs search measurement ${label:+($label) }at $ts, pid $pid ==="

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
