#!/usr/bin/env bash
# The touch daemon grabs the touchscreen: a state machine that loses a tap makes the
# screen feel dead. Runs the pure state-machine tests against fake input devices.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DAEMON="$REPO_ROOT/dots/.local/bin/touch-gestures"

[[ -f "$DAEMON" ]] || { echo "missing $DAEMON" >&2; exit 1; }
command -v python3 >/dev/null || { echo "python3 not installed; skipping" >&2; exit 0; }
python3 -c 'import evdev' 2>/dev/null \
    || { echo "python-evdev not installed; skipping" >&2; exit 0; }

exec python3 "$REPO_ROOT/tests/test_touch_gestures.py"
