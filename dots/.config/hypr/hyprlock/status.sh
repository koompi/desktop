#!/usr/bin/env bash

############ Variables ############
enable_battery=false
battery_charging=false

####### Check availability ########
for battery in "${POWER_SUPPLY_DIR:-/sys/class/power_supply}"/*BAT*; do
  if [[ -f "$battery/uevent" ]]; then
    enable_battery=true
    if [[ $(cat "$battery/status") == "Charging" ]]; then
      battery_charging=true
    fi
    break
  fi
done

############# Output #############
if [[ $enable_battery == true ]]; then
  if [[ $battery_charging == true ]]; then
    echo -n "(+) "
  fi
  echo -n "$(cat "$battery/capacity")"%
  if [[ $battery_charging == false ]]; then
    echo -n " remaining"
  fi
fi

echo ''