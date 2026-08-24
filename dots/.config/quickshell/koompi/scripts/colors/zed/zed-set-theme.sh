#!/usr/bin/env bash
set -euo pipefail

SETTINGS_PATH="${XDG_CONFIG_HOME:-$HOME/.config}/zed/settings.json"
FAMILY="KOOMPI Material"

[ -f "$SETTINGS_PATH" ] || exit 0

if grep -q '"theme"' "$SETTINGS_PATH"; then
    exit 0
fi

if jq -e . "$SETTINGS_PATH" >/dev/null 2>&1; then
    tmp="$(mktemp)"
    if jq --arg family "$FAMILY" '.theme = $family' "$SETTINGS_PATH" > "$tmp"; then
        mv "$tmp" "$SETTINGS_PATH"
    else
        rm -f "$tmp"
    fi
else
    sed -i '$ s/}/,\n  "theme": "'"${FAMILY}"'"\n}/' "$SETTINGS_PATH"
fi
