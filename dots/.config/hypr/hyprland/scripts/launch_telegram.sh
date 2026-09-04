#!/usr/bin/env bash
# Telegram hands links to the desktop default for http/https through GIO, not
# $BROWSER or xdg-open, so the only per-process override is the desktop-specific
# mimeapps list: GIO reads <name>-mimeapps.list for each name in
# XDG_CURRENT_DESKTOP before mimeapps.list. koompi-widget-mimeapps.list in
# ~/.config points http/https at koompi-open-url for this process alone, so the
# session default and the browsers' "am I the default" checks stay untouched.
set -euo pipefail
export XDG_CURRENT_DESKTOP="koompi-widget${XDG_CURRENT_DESKTOP:+:$XDG_CURRENT_DESKTOP}"
exec Telegram
