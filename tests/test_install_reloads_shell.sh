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
# shell onto exactly what it was already running. (The call may guard a die:
# since H2 a failed files step must stop the install instead of reloading.)
files_line="$(grep -n 'DO_FILES *&& install_files\|install_files || die' "$SETUP" | head -1 | cut -d: -f1)"
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

# Same ordering trap, found on a first install into a container: the global-menu
# daemon builds inside the installed config and the shell loads it from there by
# relative path, so run_setups was reaching a directory the files step had not
# created yet. Every fresh machine came up with an empty global menu.
grep -q 'setup_global_menu' "$REPO_ROOT/sdata/install/setups.sh" \
    || fail "setup_global_menu is gone from setups.sh"
grep -qE '^\s*setup_global_menu\s*$' <(sed -n '/^run_setups()/,/^}/p' "$REPO_ROOT/sdata/install/setups.sh") \
    && fail "run_setups builds the global menu again; it runs before install_files, so on a first install there is nothing to build"
menu_line="$(grep -n 'setup_global_menu' "$SETUP" | head -1 | cut -d: -f1)"
[[ -n "$menu_line" ]] || fail "setup never calls setup_global_menu, so the daemon is never built"
if [[ -n "$files_line" && -n "$menu_line" ]]; then
    (( menu_line > files_line )) || fail "setup_global_menu runs before install_files"
fi

exit "$failed"
