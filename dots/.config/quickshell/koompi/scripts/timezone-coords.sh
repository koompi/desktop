#!/usr/bin/env bash
# Prints the ISO 6709 coordinates tzdata records for the system timezone, e.g.
# +1133+10455 for Asia/Phnom_Penh. Silent when the zone has no entry.
#
# zone1970.tab drops zone names that are links, so Asia/Phnom_Penh is only
# found in the older zone.tab. Both are consulted.

set -uo pipefail

zone="$(readlink -f /etc/localtime)"
zone="${zone##*/zoneinfo/}"
[[ -n "$zone" && "$zone" != /* ]] || exit 0

for table in /usr/share/zoneinfo/zone.tab /usr/share/zoneinfo/zone1970.tab; do
    [[ -f "$table" ]] || continue
    coords="$(awk -v z="$zone" '$1 !~ /^#/ && $3 == z { print $2; exit }' "$table")"
    if [[ -n "$coords" ]]; then
        printf '%s\n' "$coords"
        exit 0
    fi
done
