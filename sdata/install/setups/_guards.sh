# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. Answers "is there a systemd to talk to", asked by every service step.

# systemctl on PATH is not a running manager. A container, a chroot and an image
# build all have the binary and no pid 1 to talk to, and every enable below then
# fails: /run/systemd/system is what sd_booted(3) itself looks for. The user
# manager is a second question, absent in any session logind did not create.
systemd_running() { [[ -d /run/systemd/system ]]; }
systemd_user_running() { systemctl --user show --property=Version >/dev/null 2>&1; }
