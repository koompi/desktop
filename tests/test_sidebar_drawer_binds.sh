#!/usr/bin/env bash
# The four right-sidebar drawer binds are three files wide: a chord in
# keybinds.lua names a GlobalShortcut in SidebarRight.qml, which calls
# showDrawer() with a page string that SidebarRightContent.qml dispatches on.
#
# A typo in the page string does not fail loudly. SidebarDrawer's sourceComponent
# ends `return timerPage`, so any unrecognised page silently opens the timer, and
# a mistyped shortcut name simply never fires. Both look like the bind not working.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SIDEBAR="$ROOT/dots/.config/quickshell/koompi/modules/koompi/sidebarRight/SidebarRight.qml"
CONTENT="$ROOT/dots/.config/quickshell/koompi/modules/koompi/sidebarRight/SidebarRightContent.qml"
BINDS="$ROOT/dots/.config/hypr/hyprland/keybinds.lua"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for f in "$SIDEBAR" "$CONTENT" "$BINDS"; do
    [[ -f "$f" ]] || fail "missing $f"
done

pages="$(grep -oE 'showDrawer\("[a-z]+"\)' "$SIDEBAR" | grep -oE '"[a-z]+"' | tr -d '"' | sort -u)"
[[ -n "$pages" ]] || fail "no showDrawer() calls in SidebarRight.qml; the drawer binds are gone"

count="$(wc -l <<< "$pages")"
[[ "$count" -eq 4 ]] || fail "expected 4 drawer pages, found $count: $(tr '\n' ' ' <<< "$pages")"

# Every page must be dispatched by name. The last branch is an unguarded default,
# so a page absent here does not fall through to nothing, it falls through to the timer.
while read -r page; do
    grep -q "drawerPage === \"$page\"" "$CONTENT" \
        || fail "page '$page' is opened by a bind but SidebarRightContent never dispatches on it, so it opens the timer instead"
done <<< "$pages"

# Every shortcut the shell declares must have a chord, and every chord a shortcut.
shortcuts="$(grep -oE 'name: "sidebarRight(Controls|Calendar|Todo|Timer)"' "$SIDEBAR" | grep -oE 'sidebarRight[A-Za-z]+' | sort -u)"
[[ "$(wc -l <<< "$shortcuts")" -eq 4 ]] || fail "expected 4 drawer GlobalShortcuts, found: $(tr '\n' ' ' <<< "$shortcuts")"

while read -r name; do
    grep -q "quickshell:$name" "$BINDS" \
        || fail "GlobalShortcut '$name' has no chord in keybinds.lua, so it can never fire"
done <<< "$shortcuts"

while read -r name; do
    grep -q "name: \"$name\"" "$SIDEBAR" \
        || fail "keybinds.lua dispatches 'quickshell:$name' but no GlobalShortcut declares it"
done < <(grep -oE 'quickshell:sidebarRight(Controls|Calendar|Todo|Timer)' "$BINDS" | sed 's/quickshell://' | sort -u)

# A bind with no description is invisible in the cheatsheet, which is how the
# welcome-guide reopen bind went unnoticed.
while read -r chord; do
    grep -q "description" <<< "$chord" \
        || fail "a drawer bind has no description and will not appear in the cheatsheet: $chord"
done < <(grep 'quickshell:sidebarRight\(Controls\|Calendar\|Todo\|Timer\)' "$BINDS")

printf 'ok: 4 drawer pages dispatched, 4 shortcuts bound, all described\n'
