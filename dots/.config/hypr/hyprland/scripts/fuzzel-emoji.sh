#!/bin/bash
set -euo pipefail

MODE="${1:-type}"

emoji="$(fuzzel --match-mode fzf --dmenu < "$(dirname "$0")/fuzzel-emoji.txt" | cut -d ' ' -f 1 | tr -d '\n')"

case "$MODE" in
    type)
        wtype "${emoji}" || wl-copy "${emoji}"
        ;;
    copy)
        wl-copy "${emoji}"
        ;;
    both)
        wtype "${emoji}" || true
        wl-copy "${emoji}"
        ;;
    *)
        echo "Usage: $0 [type|copy|both]"
        exit 1
        ;;
esac
