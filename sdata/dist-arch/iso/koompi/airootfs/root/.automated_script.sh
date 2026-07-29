#!/usr/bin/env bash
# KOOMPI OS — live-session autostart stub.  *** SKELETON ***
#
# Intent: on the live ISO this should launch the KOOMPI (Zig) installer so the
# user boots straight into the guided install/live menu.
#
# IMPORTANT: this file does NOT run on its own.  In archiso it executes only
# because root's ~/.zlogin sources it on the first VT login.  That trigger is NOT
# shipped in this skeleton (see README.md "What is stubbed").  Until the wiring
# and the koompi-installer binary exist, this stays a no-op that just prints a
# note.
#
# When complete, replace the body with something like:
#   exec /usr/local/bin/koompi-installer

set -euo pipefail

if [[ ! -x /usr/local/bin/koompi-installer ]]; then
  echo "KOOMPI live session: installer not present yet (skeleton ISO). Dropping to a shell."
  exit 0
fi

# exec /usr/local/bin/koompi-installer   # <- enable once the installer is on the ISO
