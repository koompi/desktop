#!/usr/bin/env bash
# hibernation-setup writes a swapfile, an fstab line, a mkinitcpio drop-in and
# a kernel cmdline: each one wrong is a machine that does not boot or does not
# resume. Runs the real script against a fake root (KOOMPI_HIB_ROOT) with
# btrfs, chattr, mkinitcpio, grub-mkconfig, findmnt, swapon, swaplabel and
# busctl shimmed into a log, and proves the refusals, the dry run calling
# nothing, the second run changing nothing, the HOOKS order, and the two
# callers (post_install.sh and setups/system.sh) reaching the script.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/dots/.local/share/koompi/libexec/hibernation-setup"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { printf 'FAIL: %s\n--- output ---\n%s\n--- calls ---\n%s\n' "$1" "${out:-}" "$(cat "$tmp/calls" 2>/dev/null)" >&2; exit 1; }

# shims log argv to $CALLS; "subvolume show" answers from a marker so a plain dir is not a subvolume
stub="$tmp/bin"; mkdir -p "$stub"
export CALLS="$tmp/calls" FAKE_FSTYPE=btrfs FAKE_LOGIND=na BTRFS_FAIL_CREATE=""
mk() { cat >"$stub/$1"; chmod +x "$stub/$1"; }
mk btrfs <<'EOF'
#!/usr/bin/env bash
case "$1 $2" in
    "subvolume show")   [[ -e "$3/.subvol" ]] ;;
    "subvolume create") printf 'btrfs %s\n' "$*" >>"$CALLS"; [[ -n "$BTRFS_FAIL_CREATE" ]] && exit 1; mkdir -p "$3" && touch "$3/.subvol" ;;
    "filesystem mkswapfile") printf 'btrfs %s\n' "$*" >>"$CALLS"; : >"$5" ;;
    "inspect-internal map-swapfile") echo 123456 ;;
    *) echo "unexpected btrfs $*" >&2; exit 99 ;;
esac
EOF
mk findmnt <<'EOF'
#!/usr/bin/env bash
case "$*" in
    *FSTYPE*) echo "$FAKE_FSTYPE" ;;
    *UUID*)   echo 0123abcd-0000-4000-8000-00000000cafe ;;
    *SOURCE*) echo "/dev/fake1[/@]" ;;
esac
EOF
mk swaplabel <<'EOF'
#!/usr/bin/env bash
[[ -e "$1" ]]
EOF
mk busctl <<'EOF'
#!/usr/bin/env bash
printf 's "%s"\n' "$FAKE_LOGIND"
EOF
mk logcall <<'EOF'
#!/usr/bin/env bash
printf '%s %s\n' "$(basename -- "$0")" "$*" >>"$CALLS"
EOF
for c in chattr mkinitcpio grub-mkconfig; do ln -s logcall "$stub/$c"; done
mk swapon <<'EOF'
#!/usr/bin/env bash
printf 'swapon %s\n' "$*" >>"$CALLS"
printf '%s file 1 0 0\n' "${!##"$KOOMPI_HIB_ROOT"}" >>"$KOOMPI_HIB_ROOT/proc/swaps"
EOF
export PATH="$stub:$PATH"

new_root() {
    R="$tmp/root"; rm -rf "$R"
    mkdir -p "$R/sys/power" "$R/proc" "$R/etc/default" "$R/boot/grub"
    echo 1234567890 >"$R/sys/power/image_size"
    printf 'MemTotal:        4000000 kB\nMemFree:  1 kB\n' >"$R/proc/meminfo"
    printf 'Filename\t\t\t\tType\t\tSize\t\tUsed\t\tPriority\n/dev/zram0 partition 1 1 100\n' >"$R/proc/swaps"
    echo "root=UUID=x rw quiet" >"$R/proc/cmdline"
    printf 'UUID=x / btrfs subvol=/@ 0 0\n' >"$R/etc/fstab"
    printf 'MODULES=()\nHOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck grub-btrfs-overlayfs)\n' >"$R/etc/mkinitcpio.conf"
    printf 'GRUB_DEFAULT=0\nGRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash"\nGRUB_CMDLINE_LINUX=""\n' >"$R/etc/default/grub"
    : >"$CALLS"
    export KOOMPI_HIB_ROOT="$R"
}
snapshot() { (cd "$R" && find . -type f ! -path './proc/*' -print0 | sort -z | xargs -0 md5sum); }
run_script() { out="$("$SCRIPT" "$@" 2>&1)"; rc=$?; }

# 1. Refusals: exit 0, a reason, nothing called, nothing written.
new_root; rm "$R/sys/power/image_size"; before="$(snapshot)"
run_script
(( rc == 0 )) || fail "no image_size: exit $rc, wanted 0"
[[ "$out" == *"not setting up hibernation"*image_size* ]] || fail "no image_size: no reason given"
[[ -s "$CALLS" ]] && fail "no image_size: still called something"
[[ "$before" == "$(snapshot)" ]] || fail "no image_size: wrote something"

new_root; FAKE_FSTYPE=ext4 run_script
(( rc == 0 )) || fail "ext4 root: exit $rc, wanted 0"
[[ "$out" == *"not setting up hibernation"*ext4* ]] || fail "ext4 root: reason does not name the filesystem"
[[ -s "$CALLS" ]] && fail "ext4 root: still called something"

new_root; mkdir "$R/swap"; run_script
(( rc == 0 )) || fail "plain /swap dir: exit $rc, wanted 0"
[[ "$out" == *"not a btrfs subvolume"* ]] || fail "plain /swap dir: not refused"
[[ -s "$CALLS" ]] && fail "plain /swap dir: still called something"

new_root; BTRFS_FAIL_CREATE=1 run_script
(( rc == 0 )) || fail "subvolume create failing: exit $rc, wanted 0"
[[ "$out" == *"could not create the /swap subvolume"* ]] || fail "subvolume create failing: not refused"
grep -q '^chattr\|^btrfs filesystem\|^mkinitcpio\|^grub-mkconfig' "$CALLS" && fail "subvolume create failing: carried on past it"

# 2. Root required, before anything else, when not dry-running.
if (( EUID != 0 )); then
    unset KOOMPI_HIB_ROOT; : >"$CALLS"; run_script
    (( rc == 1 )) || fail "non-root: exit $rc, wanted 1"
    [[ "$out" == *"root required"* ]] || fail "non-root: no 'root required' line"
    [[ -s "$CALLS" ]] && fail "non-root: called something before the root check"
fi

# 3. Dry run: the plan, exit 0, nothing called, nothing written.
new_root; before="$(snapshot)"; run_script --dry-run
(( rc == 0 )) || fail "dry run: exit $rc"
[[ -s "$CALLS" ]] && fail "dry run: called something"
[[ "$before" == "$(snapshot)" ]] || fail "dry run: wrote something"
for want in "would create btrfs subvolume /swap" "would create /swap/swapfile of 4000000k" \
            "would append to /etc/fstab: /swap/swapfile none swap defaults,pri=0 0 0" \
            "would write /etc/mkinitcpio.conf.d/koompi-resume.conf" "would set resume=UUID=" "nothing changed"; do
    [[ "$out" == *"$want"* ]] || fail "dry run: plan lacks '$want'"
done

# 4. The real thing, in order.
new_root; run_script
(( rc == 0 )) || fail "setup: exit $rc"
expected='btrfs subvolume create ROOT/swap
chattr +C ROOT/swap
btrfs filesystem mkswapfile -s 4000000k ROOT/swap/swapfile
swapon -p 0 ROOT/swap/swapfile
mkinitcpio -P
grub-mkconfig -o ROOT/boot/grub/grub.cfg'
[[ "$(sed "s|$R|ROOT|g" "$CALLS")" == "$expected" ]] || fail "setup: calls differ from:
$expected"
[[ -e "$R/swap/swapfile" ]] || fail "setup: no swapfile"
(( $(grep -c '^/swap/swapfile ' "$R/etc/fstab") == 1 )) || fail "setup: fstab line count is not 1"
grep -Fxq '/swap/swapfile none swap defaults,pri=0 0 0' "$R/etc/fstab" || fail "setup: fstab line is not the pri=0 one"
grep -Fxq 'UUID=x / btrfs subvol=/@ 0 0' "$R/etc/fstab" || fail "setup: the existing fstab line was lost"
[[ -f "$R/etc/fstab.koompi-hibernation.bak" ]] || fail "setup: no fstab backup"
grep -Fxq 'HOOKS+=(resume)' "$R/etc/mkinitcpio.conf.d/koompi-resume.conf" || fail "setup: drop-in lacks HOOKS+=(resume)"
grep -q 'resume' "$R/etc/mkinitcpio.conf" && fail "setup: touched /etc/mkinitcpio.conf itself"
cmdline="$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$R/etc/default/grub")"
[[ "$cmdline" == 'GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet splash resume=UUID=0123abcd-0000-4000-8000-00000000cafe resume_offset=123456"' ]] \
    || fail "setup: cmdline is $cmdline"
(( $(grep -c '^GRUB_CMDLINE_LINUX_DEFAULT=' "$R/etc/default/grub") == 1 )) || fail "setup: GRUB_CMDLINE_LINUX_DEFAULT is not a single line"
grep -Fxq 'GRUB_DEFAULT=0' "$R/etc/default/grub" || fail "setup: other grub lines lost"

# HOOKS as mkinitcpio sees them: conf then drop-in, sourced as bash
hooks="$(bash -c 'source "$1"; source "$2"; printf "%s\n" "${HOOKS[@]}"' _ "$R/etc/mkinitcpio.conf" "$R/etc/mkinitcpio.conf.d/koompi-resume.conf")"
fs_at="$(grep -nx filesystems <<<"$hooks" | cut -d: -f1)"; resume_at="$(grep -nx resume <<<"$hooks" | cut -d: -f1)"
[[ -n "$fs_at" && -n "$resume_at" ]] || fail "hooks: filesystems or resume missing from the effective HOOKS"
(( resume_at > fs_at )) || fail "hooks: resume ($resume_at) is not after filesystems ($fs_at)"
(( $(grep -cx resume <<<"$hooks") == 1 )) || fail "hooks: resume appears more than once"

# 5. Second run: nothing called, nothing changed.
before="$(snapshot)"; : >"$CALLS"; run_script
(( rc == 0 )) || fail "second run: exit $rc"
[[ -s "$CALLS" ]] && fail "second run: called something"
[[ "$before" == "$(snapshot)" ]] || fail "second run: changed a file"

# 6. A stale resume= pair (swapfile recreated elsewhere) is replaced, not joined.
sed -i 's|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT="quiet resume=UUID=old resume_offset=1 splash"|' "$R/etc/default/grub"
: >"$CALLS"; run_script
(( rc == 0 )) || fail "stale cmdline: exit $rc"
cmdline="$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$R/etc/default/grub")"
[[ "$cmdline" == 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash resume=UUID=0123abcd-0000-4000-8000-00000000cafe resume_offset=123456"' ]] \
    || fail "stale cmdline: got $cmdline"
[[ "$(cat "$CALLS")" == "grub-mkconfig -o $R/boot/grub/grub.cfg" ]] || fail "stale cmdline: expected only grub-mkconfig"

# 7. The systemd hook resumes on its own: no drop-in, no mkinitcpio, cmdline still set.
new_root; sed -i 's/^HOOKS=.*/HOOKS=(base systemd autodetect modconf block filesystems fsck)/' "$R/etc/mkinitcpio.conf"; run_script
(( rc == 0 )) || fail "systemd hook: exit $rc"
[[ -e "$R/etc/mkinitcpio.conf.d/koompi-resume.conf" ]] && fail "systemd hook: wrote a resume drop-in anyway"
grep -q '^mkinitcpio' "$CALLS" && fail "systemd hook: ran mkinitcpio for nothing"
grep -q 'resume_offset=123456' "$R/etc/default/grub" || fail "systemd hook: cmdline not set"

# 8. status: every precondition, the artifacts, logind's answer; exit follows logind.
run_script status
(( rc == 1 )) || fail "status with logind na: exit $rc, wanted 1"
for want in "kernel supports hibernation" "root filesystem is btrfs" "/swap/swapfile present" "fstab entry present" \
            "resume: systemd hook" "cmdline: resume=UUID=0123abcd-0000-4000-8000-00000000cafe resume_offset=123456" \
            "reboot pending" "logind CanHibernate: na"; do
    [[ "$out" == *"$want"* ]] || fail "status: lacks '$want'"
done
FAKE_LOGIND=yes run_script status
(( rc == 0 )) || fail "status with logind yes: exit $rc, wanted 0"

# 9. Callers: post_install.sh order and WARNING-not-abort; system.sh sudo vs --dry-run.
pi="$REPO_ROOT/installer/src/post_install.sh"
main_body="$(sed -n '/^main() {/,/^}/p' "$pi")"
order="$(grep -oE '^\s*(setup_snapshot_boot|setup_hibernation|pin_baseline)\b' <<<"$main_body" | tr -d ' ' | paste -sd ' ')"
[[ "$order" == "setup_snapshot_boot setup_hibernation pin_baseline" ]] || fail "post_install main() order is '$order'"
grep -q 'KOOMPI_HIBERNATION_SETUP:-/usr/lib/koompi/hibernation-setup' "$pi" || fail "post_install does not default to the packaged path"
printf '#!/usr/bin/env bash\necho ran-hibernation-setup\nexit 1\n' >"$tmp/failing-setup"; chmod +x "$tmp/failing-setup"
out="$(KOOMPI_HIBERNATION_SETUP="$tmp/failing-setup" bash -c 'source "$1"; setup_hibernation; echo still-running' _ "$pi" 2>&1)" \
    || fail "post_install: a failing hibernation-setup aborted the hook"
[[ "$out" == *ran-hibernation-setup*WARNING*still-running* ]] || fail "post_install: failure was not a WARNING line"
out="$(KOOMPI_HIBERNATION_SETUP="$tmp/absent" bash -c 'source "$1"; setup_hibernation; echo still-running' _ "$pi" 2>&1)" \
    || fail "post_install: a missing hibernation-setup aborted the hook"
[[ "$out" == *skipping*still-running* ]] || fail "post_install: a missing script was not a skip line"

step() { :; }; info() { :; }; ok() { :; }; warn() { printf 'warn: %s\n' "$*" >>"$tmp/warns"; }
try() { printf '%s\n' "$*" >>"$CALLS"; }
REPO_ROOT_SAVED="$REPO_ROOT"
# shellcheck source=sdata/install/setups.sh
source "$REPO_ROOT/sdata/install/setups.sh" 2>/dev/null || true
REPO_ROOT="$REPO_ROOT_SAVED"
declare -F setup_hibernation >/dev/null || fail "setups/system.sh no longer defines setup_hibernation"
grep -q '^    setup_hibernation$' "$REPO_ROOT/sdata/install/setups.sh" || fail "run_setups does not call setup_hibernation"
mkdir -p "$tmp/run/systemd/system"
systemd_running() { return 0; }
: >"$CALLS"; DRY_RUN=false setup_hibernation
[[ "$(cat "$CALLS")" == "sudo $SCRIPT" ]] || fail "setup_hibernation did not run the script under sudo (calls: $(cat "$CALLS"))"
new_root; : >"$CALLS"
out="$(DRY_RUN=true setup_hibernation 2>&1)" || fail "setup_hibernation --dry-run failed"
[[ -s "$CALLS" ]] && fail "setup_hibernation under --dry-run reached sudo"
[[ "$out" == *"would create btrfs subvolume /swap"* ]] || fail "setup_hibernation under --dry-run did not print the script's plan"

# 10. koompi doctor's line follows logind.
export KOOMPI_LOG_DIR="$tmp/logs" HOME="$tmp/home"; mkdir -p "$HOME"
out="$(FAKE_LOGIND=na "$REPO_ROOT/dots/.local/bin/koompi-health" 2>&1)"
[[ "$out" == *"hibernation: not set up (run: sudo /usr/lib/koompi/hibernation-setup"* ]] || fail "doctor: no 'not set up' line with logind na"
out="$(FAKE_LOGIND=yes "$REPO_ROOT/dots/.local/bin/koompi-health" 2>&1)"
[[ "$out" == *"hibernation: available"* ]] || fail "doctor: no 'available' line with logind yes"

echo "ok test_hibernation_setup.sh"
