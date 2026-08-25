#!/usr/bin/env bash
# wifi-powersave: NetworkManager wifi.powersave=2 (off) on laptops. Intel and
# Realtek cards dozing between beacons show up as a link that goes slow or
# drops a minute after connecting. Takes effect at the next activation.
# Gate: koompi-hw-laptop and NetworkManager installed. The file is ours, so it
# is held at this content; an admin override goes in a later-sorting file.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

conf="$KOOMPI_HW_PREFIX/etc/NetworkManager/conf.d/koompi-wifi-powersave.conf"
content='# Installed by KOOMPI apply-hardware (sdata/hardware/wifi-powersave.sh).
# Wi-Fi power saving off: dozing cards drop or stall the link on idle.
# 2 = disable, 3 = enable, 0 = driver default. Override in a later-sorting file.
[connection]
wifi.powersave = 2'

koompi-hw-laptop || hw_not_applied "not a laptop"
[[ -e "$KOOMPI_HW_PREFIX/usr/lib/systemd/system/NetworkManager.service" ]] \
    || hw_not_applied "NetworkManager is not installed"
hw_file_is "$conf" "$content" && hw_not_applied "$conf already set"

hw_write "$conf" "$content"
# conf.d is read on reload only; the installer reboots, a chroot has no daemon
if hw_systemd_running && systemctl is-active --quiet NetworkManager.service; then
    hw_do nmcli general reload conf
fi
