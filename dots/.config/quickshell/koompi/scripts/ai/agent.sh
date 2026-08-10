#!/usr/bin/env bash
# Delegate one self-contained task to the pi agent, print its answer as plain text.
# pi has bash/read/web tools, so this is how the sidebar model reaches the real
# machine and the real internet instead of answering from training data.
set -uo pipefail

TASK="${1:-}"
[ -z "$TASK" ] && { echo "No task given."; exit 0; }

TIMEOUT="${KOOMPI_AGENT_TIMEOUT:-240}"
THINKING="${KOOMPI_AGENT_THINKING:-low}"

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

# pi blocks forever on an open stdin, and Quickshell's Process hands it one
out=$(timeout "$TIMEOUT" "$PI" -p -nc --no-session --thinking "$THINKING" "$TASK" </dev/null 2>/dev/null)
code=$?

if [ "$code" -eq 124 ]; then
    echo "The agent ran out of time after ${TIMEOUT}s. Partial result, if any:"
    echo "$out"
    exit 0
fi

if [ "$code" -ne 0 ] || [ -z "${out//[[:space:]]/}" ]; then
    echo "The agent failed to answer (exit ${code}). Tell the user the lookup did not run."
    exit 0
fi

echo "$out"
