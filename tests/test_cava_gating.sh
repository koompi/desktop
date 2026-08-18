#!/usr/bin/env bash
# Cava is a 32-bar/24fps process reading the audio monitor; every consumer of its
# output (bar strip, media popup, sidebar player card) already flattens to a line
# via WaveVisualizer.live when the active player isn't playing. So the process
# itself has to be gated on Playing alone - a paused player, or a panel that merely
# COULD show one, buys nothing visible and was the exact regression this test
# guards: `wanted` briefly read `GlobalStates.mediaControlsOpen || isPlaying`, which
# started cava the moment the media popup opened on a paused player.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CAVA="$REPO_ROOT/dots/.config/quickshell/koompi/services/Cava.qml"

[[ -f "$CAVA" ]] || { echo "missing $CAVA" >&2; exit 1; }

wanted_line="$(grep -A2 'readonly property bool wanted:' "$CAVA")"

echo "$wanted_line" | grep -q 'MprisController\.isPlaying' \
    || { echo "Cava.wanted no longer reads MprisController.isPlaying:" >&2; echo "$wanted_line" >&2; exit 1; }

if echo "$wanted_line" | grep -qE 'mediaControlsOpen|hasActiveMedia'; then
    echo "Cava.wanted ORs in a panel-open or has-a-player condition alongside isPlaying:" >&2
    echo "$wanted_line" >&2
    echo >&2
    echo "That starts the process for a paused player (panel open) or any non-stopped" >&2
    echo "player (hasActiveMedia), neither of which WaveVisualizer renders as anything" >&2
    echo "but a flat line. wanted must be isPlaying alone." >&2
    exit 1
fi

echo "ok: Cava.wanted is MprisController.isPlaying alone"
