# Sourced from zsh, not executed - no shebang. Contents are POSIX sh.
# shellcheck shell=sh

# Auto start Hyprland on tty1
if [ -z "$DISPLAY" ] && [ "$XDG_VTNR" -eq 1 ]; then
  mkdir -p ~/.cache
  exec start-hyprland > ~/.cache/hyprland.log 2>&1
fi
