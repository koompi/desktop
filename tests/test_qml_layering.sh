#!/usr/bin/env bash
# Which way the shell's dependencies point. `modules/` is the UI and `services/` is
# what it talks to; a service that imports a UI package makes the two circular, and
# QML does not report a cycle - it reports the service as not being a type at all,
# from a stack that names neither file.
#
# This is not theoretical. services/ai/FeedbackService.qml imported the feedback
# window package to host two LazyLoaders, and the whole shell failed to load with
# "FeedbackService is not a type". Eleven jobs and fifty-one tests missed it because
# nothing in the suite instantiates the QML tree.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SERVICES="$SHELL_ROOT/services"

[[ -d "$SERVICES" ]] || { echo "missing $SERVICES" >&2; exit 1; }

offenders="$(grep -rnE '^[[:space:]]*import[[:space:]]+qs\.modules\.koompi\b|^[[:space:]]*import[[:space:]]+qs\.modules\.waffle\b' "$SERVICES" 2>/dev/null)"
if [[ -n "$offenders" ]]; then
    echo "a service imports a UI package, which makes the dependency circular:" >&2
    echo "$offenders" >&2
    echo >&2
    echo "Move whatever needs the UI into modules/ or into panelFamilies/." >&2
    exit 1
fi

# The windows a service used to own are loaded by the panel family instead. If they
# stop being loaded there, nothing opens them and the feature is silently gone.
FAMILY="$SHELL_ROOT/panelFamilies/KoompiFamily.qml"
for window in FeedbackWindow CorrectionWindow MemoryBrowserWindow Intelligence; do
    grep -q "component: $window" "$FAMILY" \
        || { echo "$window is no longer loaded by KoompiFamily.qml" >&2; exit 1; }
done

# services/ may use qs.modules.common - that is shared, not UI - so say what stayed
# allowed rather than leaving the next reader to guess from an empty pass.
common="$(grep -rlE '^[[:space:]]*import[[:space:]]+qs\.modules\.common' "$SERVICES" | wc -l)"
echo "ok: no service imports a UI package ($common still import qs.modules.common, which is shared)"
