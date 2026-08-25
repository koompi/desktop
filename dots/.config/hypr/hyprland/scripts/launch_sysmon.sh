#!/usr/bin/env bash
# rules.lua pins TUI.sysmon-scratch to special:sysmon
exec koompi-launch-tui sysmon-scratch sh -c 'btop || htop || top'
