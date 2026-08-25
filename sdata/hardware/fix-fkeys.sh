#!/usr/bin/env bash
# fix-fkeys: F1-F12 on Apple-style keyboards (Apple, Lofree Flow, Keychron in
# Mac mode) act as F-keys; hid_apple's default fnmode=1 makes them media keys.
# Port of omarchy install/hardware/fix-fkeys.sh. Gate: an installed kernel
# ships hid_apple. An existing hid_apple.conf is someone's choice; left alone.
set -euo pipefail
# shellcheck source-path=SCRIPTDIR
# shellcheck source=lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/lib.sh"

conf="$KOOMPI_HW_PREFIX/etc/modprobe.d/hid_apple.conf"

hw_kernel_ships drivers/hid/hid-apple || hw_not_applied "no installed kernel ships hid_apple"
[[ -f "$conf" ]] && hw_not_applied "$conf exists; leaving it as found"

hw_write "$conf" "options hid_apple fnmode=2"
