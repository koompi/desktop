#!/usr/bin/env bash
# Launch WhatsApp Web as a dedicated app-window in the first available
# chromium-family browser (WhatsApp has no native Linux app). The resulting
# window class contains "web.whatsapp.com", which the scratchpad window rules
# in hyprland/rules.lua match on. Firefox/zen are intentionally excluded: they
# don't support Chromium's --app dedicated-window mode.
exec "$HOME/.config/hypr/hyprland/scripts/launch_first_available.sh" \
    'google-chrome-stable --app=https://web.whatsapp.com' \
    'chromium --app=https://web.whatsapp.com' \
    'brave --app=https://web.whatsapp.com' \
    'microsoft-edge-stable --app=https://web.whatsapp.com' \
    'vivaldi-stable --app=https://web.whatsapp.com'
