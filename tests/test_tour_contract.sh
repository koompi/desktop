#!/usr/bin/env bash
# The tour is a new shell surface, so docs/navigation.md governs it, and its
# steps drive real surfaces by name - which is the part that fails silently.
#
# A `demo` naming a GlobalStates property that does not exist sets a stray
# property on the singleton and opens nothing. Nothing warns; the step just
# looks broken to whoever is being taught the desktop with it.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_DIR="$ROOT/dots/.config/quickshell/koompi"
TOUR="$SHELL_DIR/modules/koompi/tour/Tour.qml"
STEPS="$SHELL_DIR/modules/koompi/tour/steps.js"
STATES="$SHELL_DIR/GlobalStates.qml"
BINDS="$ROOT/dots/.config/hypr/hyprland/keybinds.lua"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for f in "$TOUR" "$STEPS" "$STATES" "$BINDS"; do
    [[ -f "$f" ]] || fail "missing $f"
done

# Every demo names a real flag, and that flag really gates its surface.
mapfile -t demos < <(grep -oP 'demo:\s*"\K[^"]+' "$STEPS" | sort -u)
(( ${#demos[@]} )) || fail "no steps drive a surface; the tour shows pictures instead of the desktop"
for flag in "${demos[@]}"; do
    grep -q "property bool $flag" "$STATES" \
        || fail "steps.js opens '$flag', which GlobalStates does not declare - it would open nothing, silently"
    grep -rqE "(visible|active):.*GlobalStates\.$flag" "$SHELL_DIR/modules" \
        || fail "'$flag' gates no surface, so the step naming it demonstrates nothing"
done

# docs/navigation.md: register with the grab AND gate keyboard focus, both.
grep -q 'GlobalFocusGrab.addPersistent' "$TOUR" \
    || fail "the tour does not register with GlobalFocusGrab"
grep -q 'GlobalFocusGrab.removePersistent' "$TOUR" \
    || fail "the tour never leaves the grab, holding it active for the session"
grep -q 'addDismissable' "$TOUR" \
    && fail "the tour is dismissable; the first surface a step opens takes the grab and closes it"
grep -qE 'keyboardFocus:.*GlobalStates\.tourOpen.*WlrKeyboardFocus' "$TOUR" \
    || fail "keyboard focus is not gated on tourOpen"

# One keyboard entry point, and a bind the cheatsheet can show.
entries="$(grep -c 'quickshell:tourToggle' "$BINDS")"
(( entries == 1 )) || fail "the tour has $entries keyboard entry points; the model allows exactly one"
grep -qE 'hl\.bind\("[^"]*tour|tourToggle' "$BINDS" \
    || fail "no bind reaches the tour"
grep -q 'quickshell:tourToggle.*description = "Shell: ' "$BINDS" \
    || fail "the tour bind has no group-prefixed description, so it never appears in the cheatsheet"

# Content is data: the steps live in a list, not in the layout.
grep -q 'Steps.steps' "$TOUR" || fail "Tour.qml no longer reads its steps from steps.js"
count="$(grep -c 'icon:' "$STEPS")"
(( count >= 10 )) || fail "only $count steps; criterion 2 asks for the whole desktop"

# Criterion 7: whatever ends the tour has to put the desktop back.
grep -qE 'applyDemo\(""\)' "$TOUR" \
    || fail "close() does not clear the demonstrated surface; the tour leaves a panel open behind it"

# Loaded in both panel families, or one of them silently has no tour.
for fam in KoompiFamily WaffleFamily; do
    grep -q 'component: Tour {}' "$SHELL_DIR/panelFamilies/$fam.qml" \
        || fail "$fam does not load the tour"
done

echo "ok"
