#!/usr/bin/env bash
# KOOMPI OS live-session autostart stub. SKELETON.
#
# Does not run on its own: in archiso it executes only because root's ~/.zlogin
# sources it on the first VT login, and that trigger is not shipped here (see
# README.md). A no-op until the wiring and the koompi-installer binary exist.
#
# When complete the body becomes: exec /usr/local/bin/koompi-installer

set -euo pipefail

if [[ ! -x /usr/local/bin/koompi-installer ]]; then
  echo "KOOMPI live session: installer not present yet (skeleton ISO). Dropping to a shell."
  exit 0
fi

# exec /usr/local/bin/koompi-installer   # <- enable once the installer is on the ISO
