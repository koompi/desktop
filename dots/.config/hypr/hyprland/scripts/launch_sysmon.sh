#!/usr/bin/env bash
# Unique app_id so rules.lua can pin it to special:sysmon.
exec wezterm start --class sysmon-scratch -- sh -c 'btop || htop || top'
