#!/usr/bin/env bash
# Toggle an app as a scratchpad "chat widget" on its own special workspace.
#
# Placement (which special workspace + float/size/center) is owned by the window
# rules in hyprland/rules.lua, matched by window class. This script only owns
# "launch it if it isn't running yet" and "show/hide the scratchpad". First press
# launches the app (the rule drops it on the hidden special workspace) then reveals
# it; every later press just shows/hides it.
#
# Usage: toggle_app_scratchpad.sh <special-name> <class-regex> <launch-cmd...>
#
# NOTE: this DE drives Hyprland through the Lua plugin, which evaluates
# `hyprctl dispatch <arg>` as Lua (return hl.dispatch(<arg>)). Dispatches must
# therefore be written in the plugin's hl.dsp.* form, not native dispatcher syntax.
special="$1"
classre="$2"
shift 2
launch="$*"

if [ -z "$special" ] || [ -z "$classre" ] || [ -z "$launch" ]; then
    notify-send "App widget" "Usage: toggle_app_scratchpad.sh <special> <class-regex> <launch...>" 2>/dev/null
    exit 1
fi

running() {
    hyprctl clients -j | jq -e --arg c "$classre" 'any(.[]; (.class // "") | test($c; "i"))' >/dev/null 2>&1
}

if running; then
    hyprctl dispatch "hl.dsp.workspace.toggle_special(\"${special}\")"
else
    hyprctl dispatch "hl.dsp.exec_cmd(\"${launch}\")"
    for _ in $(seq 1 80); do
        running && break
        sleep 0.1
    done
    hyprctl dispatch "hl.dsp.workspace.toggle_special(\"${special}\")"
fi
