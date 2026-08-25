# KOOMPI vendor quirks

One script per model or model family, run by `all.sh` before the generic quirks.
Each gates on the DMI strings, so the whole directory is safe to run on every machine:

```bash
#!/usr/bin/env bash
# <model>: what is wrong on this machine and what this fixes.
set -euo pipefail
# shellcheck source=../lib.sh
source "$(dirname -- "${BASH_SOURCE[0]}")/../lib.sh"

koompi-hw-match '<product_name or product_family>' || hw_not_applied "not a <model>"
# ... hw_write / hw_do, idempotent: check first, change only what differs
```

Then add `run_quirk koompi/<model>.sh` to `all.sh` above the generic rows.

Empty on purpose: as of 2026-08-25 no KOOMPI model's DMI strings are recorded anywhere in this repository.
Read them off a machine with `cat /sys/class/dmi/id/{sys_vendor,product_name,product_family,chassis_type}` and put the values in the script header.
