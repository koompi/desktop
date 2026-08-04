#!/usr/bin/env bash
# An install into a running session left that session on the old files: Quickshell
# holds its QML and its config in memory, so migrate_quick_toggles rewrote
# config.json and the screen kept showing the old toggles. The install path has to
# restart the shell the way the update path always has, and the closing message
# must not keep claiming `hyprctl reload` covers it.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$REPO_ROOT/setup"

failed=0
fail() { echo "FAIL: $*" >&2; failed=1; }

grep -q 'reload_session' "$SETUP" \
    || fail "setup never calls reload_session; an install leaves the old shell running"

# It has to follow install_files: reloading before the files land restarts the
# shell onto exactly what it was already running.
files_line="$(grep -n 'DO_FILES *&& install_files' "$SETUP" | head -1 | cut -d: -f1)"
reload_line="$(grep -n 'DO_FILES *&& reload_session' "$SETUP" | head -1 | cut -d: -f1)"
[[ -n "$files_line" ]] || fail "cannot find the install_files call"
[[ -n "$reload_line" ]] || fail "reload_session is not gated on DO_FILES"
if [[ -n "$files_line" && -n "$reload_line" ]]; then
    (( reload_line > files_line )) || fail "reload_session runs before install_files"
fi

# The old message told people `hyprctl reload` picks up the new config. It reloads
# Hyprland, not Quickshell, which is why an update read as having done nothing.
grep -q 'hyprctl reload.*picks up the new config' "$SETUP" \
    && fail "the closing message still claims hyprctl reload picks up the shell config"

# reload_session reports what actually happened, including the no-session case.
# A fixed closing line can only contradict it.
grep -qi 'shell restarted above\|session was reloaded' "$SETUP" \
    && fail "the closing message asserts a restart reload_session may not have done"

exit "$failed"
