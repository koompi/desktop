#!/usr/bin/env bash
# Chromium --app only; firefox/zen have no dedicated-window mode.
exec "$HOME/.config/hypr/hyprland/scripts/launch_first_available.sh" \
    'google-chrome-stable --app=https://web.whatsapp.com' \
    'chromium --app=https://web.whatsapp.com' \
    'brave --app=https://web.whatsapp.com' \
    'microsoft-edge-stable --app=https://web.whatsapp.com' \
    'vivaldi-stable --app=https://web.whatsapp.com'
