#!/usr/bin/env bash
# Usage: toggle_app_scratchpad.sh <special-name> <class-regex> <launch-cmd...>
# Placement is owned by the window rules in hyprland/rules.lua.
#
# This DE drives Hyprland through the Lua plugin, which evaluates `hyprctl dispatch
# <arg>` as Lua. Dispatches must be written in hl.dsp.* form, not native syntax.
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
