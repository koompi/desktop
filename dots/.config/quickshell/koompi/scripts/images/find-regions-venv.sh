#!/usr/bin/env bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# shellcheck source=/dev/null
source "$(eval echo "$ILLOGICAL_IMPULSE_VIRTUAL_ENV")/bin/activate"
"$SCRIPT_DIR/find_regions.py" "$@"
deactivate
