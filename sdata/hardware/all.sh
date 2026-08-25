# shellcheck shell=bash
# Sourced by libexec/apply-hardware, which defines run_quirk. Vendor quirks
# (koompi/<model>.sh, gated on koompi-hw-match) go first, generic ones after.
# Every script is a no-op when its predicate says no, so the whole list runs
# on every machine and after every update. koompi/ is empty: no KOOMPI model's
# DMI strings are recorded anywhere in this repo yet (see koompi/README.md).

run_quirk fix-fkeys.sh
run_quirk wifi-powersave.sh
