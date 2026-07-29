#!/usr/bin/env bash
# System-monitor scratchpad body. kitty launched with a unique --class
# (sysmon-scratch) so the window rules in hyprland/rules.lua can pin it to the
# special:sysmon workspace. Runs btop, falling back to htop then top, so the
# widget works even before btop is installed (btop has the nicest UI - install
# it with `sudo pacman -S btop` to get it).
exec kitty --class sysmon-scratch sh -c 'btop || htop || top'
