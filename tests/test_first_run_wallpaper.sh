#!/usr/bin/env bash
# A missing first_run.txt is not proof of a first run.
#
# `handleFirstRun()` used to switch the wallpaper to the default unconditionally,
# so any existing user who lost that marker - a cleared state directory, a
# restored home, a test - silently lost their wallpaper AND the colour scheme
# generated from it. Observed on 2026-08-04: clearing the marker by hand reset
# `background.wallpaperPath` to `default_wallpaper.png` and regenerated
# colors.json within the same second.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/dots/.config/quickshell/koompi/services/FirstRunExperience.qml"
CONFIG="$ROOT/dots/.config/quickshell/koompi/modules/common/Config.qml"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$SRC" ]] || fail "missing $SRC"

body="$(awk '/function handleFirstRun/,/^    }/' "$SRC")"
[[ -n "$body" ]] || fail "handleFirstRun() is gone from $SRC"

grep -q 'wallpaperSwitchScriptPath' <<< "$body" \
    || fail "handleFirstRun() no longer sets a default wallpaper at all; a genuine first run needs one"

# The guard, not merely the presence of an if: the switch must be reachable only
# when no wallpaper is configured.
grep -q 'Config\.options\.background\.wallpaperPath' <<< "$body" \
    || fail "handleFirstRun() switches the wallpaper without reading the configured one, so a lost marker destroys it"

guard_line="$(grep -n 'Config\.options\.background\.wallpaperPath' <<< "$body" | head -1 | cut -d: -f1)"
switch_line="$(grep -n 'wallpaperSwitchScriptPath' <<< "$body" | head -1 | cut -d: -f1)"
(( guard_line < switch_line )) \
    || fail "the wallpaper switch runs before the guard reads the configured path"

# The guard leans on "" being the default, so a real default here would make an
# existing user indistinguishable from a first run and the guard would never fire.
grep -A1 'property string wallpaperPath' "$CONFIG" | grep -q 'wallpaperPath: *""' \
    || fail "Config.background.wallpaperPath no longer defaults to \"\"; the first-run guard cannot tell a new user from an existing one"

# The guide itself must still launch on a first run, guarded or not.
grep -q 'welcomeQmlPath' <<< "$body" \
    || fail "handleFirstRun() no longer launches the welcome guide"
grep -q 'welcomeQmlPath' <<< "$(sed -n "${switch_line},\$p" <<< "$body")" \
    || fail "the welcome guide launch moved inside the wallpaper guard; it must run on every first run"

echo "ok"
