#!/usr/bin/env bash
# Delegate one self-contained task to the pi agent, print its answer as plain text.
# pi has bash/read/web tools, so this is how the sidebar model reaches the real
# machine and the real internet instead of answering from training data.
#
# The run also narrates itself into $RUNDIR so the sidebar can watch it: `status`
# is six lines of state, `task` is the question, `output` grows while pi works.
# `agent.sh --cancel` stops a run and everything it started.
set -uo pipefail
umask 077

RUNDIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell/ai/agent"
TIMEOUT="${KOOMPI_AGENT_TIMEOUT:-240}"
THINKING="${KOOMPI_AGENT_THINKING:-low}"

now_ms() { date +%s%3N; }

# One field per line so the UI needs no JSON parser, renamed into place so a
# reader never catches half of it.
# state / startedMs / finishedMs / pgid / exitCode / timeoutSec
write_status() { # state finishedMs exitCode
    printf '%s\n%s\n%s\n%s\n%s\n%s\n' \
        "$1" "${STARTED:-0}" "${2:-0}" "${PGID:-0}" "${3:-0}" "$TIMEOUT" > "$RUNDIR/status.new"
    mv -f "$RUNDIR/status.new" "$RUNDIR/status"
}

if [ "${1:-}" = "--cancel" ]; then
    [ -r "$RUNDIR/status" ] || exit 0
    mapfile -t state < "$RUNDIR/status"
    [ "${state[0]:-}" = "running" ] || exit 0
    pgid="${state[3]:-0}"
    [ "$pgid" -gt 1 ] 2>/dev/null || exit 0
    : > "$RUNDIR/cancelled"
    kill -TERM "-$pgid" 2>/dev/null
    for _ in $(seq 30); do
        kill -0 "-$pgid" 2>/dev/null || exit 0
        sleep 0.1
    done
    kill -KILL "-$pgid" 2>/dev/null
    exit 0
fi

TASK="${1:-}"
[ -z "$TASK" ] && { echo "No task given."; exit 0; }

PI="$(command -v pi || true)"
for candidate in "$HOME/.npm-global/bin/pi" "$HOME/.local/bin/pi" /usr/local/bin/pi; do
    [ -n "$PI" ] && break
    [ -x "$candidate" ] && PI="$candidate"
done

if [ -z "$PI" ]; then
    echo "The pi agent is not installed on this machine, so this lookup cannot run."
    exit 0
fi

cd "$HOME" || exit 0

mkdir -p "$RUNDIR"
chmod 700 "$RUNDIR"
rm -f "$RUNDIR/cancelled"
: > "$RUNDIR/output"
: > "$RUNDIR/events.ndjson"
printf '%s\n' "$TASK" > "$RUNDIR/task"
STARTED="$(now_ms)"
PGID=0
write_status running

# pi in text mode prints nothing until it is finished, which is what left the UI
# with a spinner for four minutes. `--mode json` narrates every tool call as it
# happens; jq turns that stream into the log the activity panel tails.
# pi prints its help on stderr, and a pipe into `grep -q` would trip pipefail
JSON_MODE=0
if command -v jq >/dev/null 2>&1 && grep -q -- '--mode' <<<"$("$PI" --help 2>&1)"; then
    JSON_MODE=1
fi

run_agent() {
    # job control is what put this subshell in its own group; leaving it on here
    # would put the pipeline in a third group that the cancel never reaches
    set +m
    # pi blocks forever on an open stdin, and Quickshell's Process hands it one
    if [ "$JSON_MODE" = 1 ]; then
        timeout --foreground -k 5 "$TIMEOUT" "$PI" -p -nc --no-session --thinking "$THINKING" --mode json "$TASK" </dev/null 2>/dev/null \
            | tee "$RUNDIR/events.ndjson" \
            | jq -j --unbuffered '
                if .type == "tool_execution_start" then
                    "$ " + .toolName + " " + ((.args.command // .args.path // .args.url // (.args | tostring)) | tostring) + "\n"
                elif .type == "tool_execution_end" then
                    (if .isError then "  failed\n" else "  ok\n" end)
                elif .assistantMessageEvent.type == "text_delta" then
                    .assistantMessageEvent.delta
                elif .type == "turn_end" then "\n"
                else empty end
            ' >> "$RUNDIR/output" 2>/dev/null
        return "${PIPESTATUS[0]}"
    fi
    timeout --foreground -k 5 "$TIMEOUT" "$PI" -p -nc --no-session --thinking "$THINKING" "$TASK" </dev/null 2>/dev/null > "$RUNDIR/output"
}

# Job control gives the pipeline its own process group, so cancelling it takes pi
# and every tool pi spawned. Killing the parent alone leaves those behind.
set -m
run_agent &
child=$!
set +m

pgid="$(ps -o pgid= -p "$child" 2>/dev/null | tr -d ' ')"
# never record a group this run does not lead: killing that would take the shell
if [ -n "$pgid" ] && [ "$pgid" = "$child" ]; then PGID="$pgid"; fi
write_status running

stop_group() {
    [ "${PGID:-0}" -gt 1 ] 2>/dev/null && kill -TERM "-$PGID" 2>/dev/null
    return 0
}
# Quickshell kills this script, not the group, when it drops the Process
trap 'stop_group; write_status cancelled "$(now_ms)" 143; exit 143' TERM INT HUP

wait "$child"
code=$?
trap - TERM INT HUP
# `timeout` signals pi alone, so on a deadline the tools pi started can outlive it
stop_group

if [ "$JSON_MODE" = 1 ]; then
    out="$(jq -r 'select(.assistantMessageEvent.type == "text_end") | .assistantMessageEvent.content' "$RUNDIR/events.ndjson" 2>/dev/null)"
else
    out="$(cat "$RUNDIR/output" 2>/dev/null)"
fi

finished="$(now_ms)"
elapsed=$(( (finished - STARTED) / 1000 ))

if [ -e "$RUNDIR/cancelled" ]; then
    write_status cancelled "$finished" "$code"
    echo "The user stopped the agent after ${elapsed}s, so it has no answer to report."
    if [ -n "${out//[[:space:]]/}" ]; then
        echo "What it had found before it was stopped:"
        echo "$out"
    fi
    exit 0
fi

if [ "$code" -eq 124 ] || [ "$code" -eq 137 ]; then
    write_status timeout "$finished" "$code"
    echo "The agent ran out of time after ${TIMEOUT}s. Partial result, if any:"
    echo "$out"
    exit 0
fi

if [ "$code" -ne 0 ] || [ -z "${out//[[:space:]]/}" ]; then
    write_status failed "$finished" "$code"
    echo "The agent failed to answer (exit ${code}). Tell the user the lookup did not run."
    exit 0
fi

write_status done "$finished" "$code"
echo "$out"
