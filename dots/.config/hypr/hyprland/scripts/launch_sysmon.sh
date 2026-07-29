#!/usr/bin/env bash
# System-monitor scratchpad body. WezTerm launched with a unique Wayland app_id
# (sysmon-scratch) so the window rules in hyprland/rules.lua can pin it to the
# special:sysmon workspace. Runs btop, falling back to htop then top, so the
# widget works even before btop is installed.
exec wezterm start --class sysmon-scratch -- sh -c 'btop || htop || top'
