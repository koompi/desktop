#!/usr/bin/env bash
# The fingerprint enrolment path (OMARCHY-AUDIT O15), driven against shims:
#   - koompi-hw-fingerprint reads a fake sysfs tree, so the reader rules are
#     exercised on a machine with or without one;
#   - koompi-lid --closed reads a fake ACPI directory;
#   - koompi-setup-fingerprint runs with fprintd-enroll, fprintd-list, sudo,
#     busctl and koompi-notify-send shimmed on PATH and its PAM files under a
#     temp KOOMPI_PAM_ROOT, so nothing here enrols, deletes or edits anything
#     on this machine.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_ROOT/dots/.local/bin"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# --- koompi-hw-fingerprint ---------------------------------------------------
usb="$WORK/usb"
add_dev() { # name vendor product-id [product-string] [interface-driver]
    local d="$usb/$1"
    mkdir -p "$d/$1:1.0"
    printf '%s\n' "$2" > "$d/idVendor"
    printf '%s\n' "$3" > "$d/idProduct"
    [[ -n "${4:-}" ]] && printf '%s\n' "$4" > "$d/product"
    if [[ -n "${5:-}" ]]; then
        mkdir -p "$WORK/drivers/$5"
        ln -s "$WORK/drivers/$5" "$d/$1:1.0/driver"
    fi
}
hw() { KOOMPI_USB_DEVICES_PATH="$usb" "$BIN/koompi-hw-fingerprint" "$@"; }

mkdir -p "$usb"
add_dev usb1 1d6b 0002 "xHCI Host Controller"
add_dev 1-3 5986 216b "Integrated RGB Camera" uvcvideo
out="$(hw 2>&1)"; rc=$?
[[ $rc -eq 1 && -z "$out" ]] || fail "no reader: want exit 1 and no output, got rc=$rc out='$out'"
out="$(hw --verbose 2>&1)"
grep -q 'no fingerprint reader' <<< "$out" || fail "no reader --verbose: expected a 'no fingerprint reader' line, got '$out'"

# Same vendor as a reader, but the kernel drives it (a Synaptics touchpad).
add_dev 1-4 06cb 0aaa "" usbhid
hw && fail "a 06cb device with usbhid bound counted as a reader"

# This machine's reader: Synaptics 06cb:0123, no product string, no driver.
add_dev 1-5.4 06cb 0123
out="$(hw --verbose 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "06cb device without a driver: want exit 0, got $rc"
grep -q '1-5.4: vendor 06cb:0123' <<< "$out" || fail "--verbose did not name the vendor match: '$out'"
out="$(hw 2>&1)"
[[ -z "$out" ]] || fail "without --verbose a match must stay silent, got '$out'"

# usbfs is libusb's claim while fprintd works the reader: still a reader.
rm -rf "$usb/1-5.4"; add_dev 1-5.4 06cb 0123 "" usbfs
hw || fail "a 06cb device bound to usbfs was not counted as a reader"

# A named reader from a vendor off the list.
rm -rf "$usb/1-5.4"; add_dev 1-6 04f3 0c4b "ELAN:ARM-M4" usbhid
out="$(hw --verbose 2>&1)" || fail "ELAN:ARM-M4 product string was not counted as a reader"
grep -q "product string 'ELAN:ARM-M4'" <<< "$out" || fail "--verbose did not name the product-string match: '$out'"
rm -rf "$usb/1-6"; add_dev 1-6 27c6 55a4 "Goodix Fingerprint USB Device"
hw || fail "'Goodix Fingerprint USB Device' was not counted as a reader"
rm -rf "$usb/1-6"
hw --bogus 2> /dev/null; [[ $? -eq 64 ]] || fail "unknown flag should exit 64"
echo "ok   koompi-hw-fingerprint: silent exit 1 with no reader; vendor, driver, usbfs and product-string rules"

# --- koompi-lid --closed -----------------------------------------------------
lid="$WORK/lid"
mkdir -p "$lid/LID0"
printf 'state:      closed\n' > "$lid/LID0/state"
KOOMPI_LID_STATE_DIR="$lid" "$BIN/koompi-lid" --closed || fail "koompi-lid --closed: closed lid should exit 0"
printf 'state:      open\n' > "$lid/LID0/state"
KOOMPI_LID_STATE_DIR="$lid" "$BIN/koompi-lid" --closed && fail "koompi-lid --closed: open lid should exit 1"
KOOMPI_LID_STATE_DIR="$WORK/nolid" "$BIN/koompi-lid" --closed && fail "koompi-lid --closed: no lid switch should exit 1 (desktop)"
echo "ok   koompi-lid --closed: 0 closed, 1 open, 1 without a lid switch"

# --- koompi-setup-fingerprint ------------------------------------------------
shims="$WORK/shims"; mkdir -p "$shims"
log="$WORK/calls.log"
cat > "$shims/fprintd-enroll" <<'SH'
#!/usr/bin/env bash
printf 'fprintd-enroll %s\n' "$*" >> "$CALLS"
exit "${ENROLL_RC:-0}"
SH
cat > "$shims/fprintd-list" <<'SH'
#!/usr/bin/env bash
printf 'fprintd-list %s\n' "$*" >> "$CALLS"
echo "Using device /net/reactivated/Fprint/Device/0"
if [[ "${PRINTS:-0}" -gt 0 ]]; then
    echo "Fingerprints for user $1 on Synaptics Sensors (press):"
    for ((i = 0; i < PRINTS; i++)); do echo " - #$i: right-index-finger"; done
else
    echo "User $1 has no fingers enrolled for Synaptics Sensors (press)."
fi
SH
cat > "$shims/sudo" <<'SH'
#!/usr/bin/env bash
printf 'sudo %s\n' "$*" >> "$CALLS"
exec "$@"
SH
cat > "$shims/busctl" <<'SH'
#!/usr/bin/env bash
echo "b true"
SH
cat > "$shims/koompi-notify-send" <<'SH'
#!/usr/bin/env bash
printf 'koompi-notify-send' >> "$CALLS"; printf ' [%s]' "$@" >> "$CALLS"; printf '\n' >> "$CALLS"
SH
chmod +x "$shims"/*
# The real detector and lid query, on the fake trees.
ln -s "$BIN/koompi-hw-fingerprint" "$shims/koompi-hw-fingerprint"

root="$WORK/root"
mkdir -p "$root/etc/pam.d" "$root/usr/lib/pam.d"
printf '#%%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n' > "$root/etc/pam.d/sudo"
printf '#%%PAM-1.0\n\nauth       include      system-auth\naccount    include      system-auth\npassword   include      system-auth\nsession    include      system-auth\n' > "$root/usr/lib/pam.d/polkit-1"

setup() { # stdin answers; PRINTS and ENROLL_RC from the environment
    PATH="$shims:$PATH" CALLS="$log" KOOMPI_USB_DEVICES_PATH="$usb" KOOMPI_PAM_ROOT="$root" \
        "$BIN/koompi-setup-fingerprint" "$@"
}
: > "$log"

# No reader: says so, exits 1, touches nothing.
out="$(setup < /dev/null 2>&1)"; rc=$?
[[ $rc -eq 1 ]] || fail "setup with no reader: want exit 1, got $rc"
grep -q 'no fingerprint reader' <<< "$out" || fail "setup with no reader should say why, got '$out'"
[[ ! -s "$log" ]] || fail "setup with no reader called something: $(cat "$log")"
out="$(setup --invite 2>&1)"; rc=$?
[[ $rc -eq 0 && -z "$out" && ! -s "$log" ]] || fail "--invite with no reader: want silent exit 0 and no toast, got rc=$rc out='$out' calls='$(cat "$log")'"

add_dev 1-5.4 06cb 0123

# Invite: a reader with prints already enrolled sends nothing.
PRINTS=1 setup --invite || fail "--invite with a print enrolled: want exit 0"
grep -q 'koompi-notify-send' "$log" && fail "--invite sent a toast although a finger is enrolled"
# A reader with none: one toast whose click opens this setup in a terminal.
: > "$log"
PRINTS=0 setup --invite || fail "--invite with no prints: want exit 0"
grep -q '^koompi-notify-send .*\[--exec\] \[.*/koompi-setup-fingerprint\] \[--terminal\]$' "$log" \
    || fail "--invite did not send a toast whose --exec is 'koompi-setup-fingerprint --terminal': $(cat "$log")"
grep -q '\[-u\] \[critical\]' "$log" || fail "the first-run toast should be critical so it does not time out unseen"
echo "ok   --invite: silent without a reader or with a print enrolled; one --exec toast otherwise"

# --terminal: the first terminal in variables.lua's order, with its own way of
# running a command, gets this script with --hold so the window stays open.
cat > "$shims/wezterm" <<'SH'
#!/usr/bin/env bash
printf 'wezterm' >> "$CALLS"; printf ' [%s]' "$@" >> "$CALLS"; printf '\n' >> "$CALLS"
SH
chmod +x "$shims/wezterm"
: > "$log"
setup --terminal --finger left-thumb || fail "--terminal: want exit 0"
grep -q '^wezterm \[start\] \[--\] \[.*/koompi-setup-fingerprint\] \[--hold\] \[--finger\] \[left-thumb\]$' "$log" \
    || fail "--terminal did not run 'wezterm start -- koompi-setup-fingerprint --hold --finger left-thumb': $(cat "$log")"
rm -f "$shims/wezterm"
echo "ok   --terminal: wezterm start -- <self> --hold, the finger carried along"

# Enrol, decline both stacks: fprintd-enroll runs for this user with the
# default finger, and sudo is never called.
: > "$log"
out="$(printf 'n\nn\n' | setup 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "enrol + decline: want exit 0, got $rc: $out"
grep -q "^fprintd-enroll -f right-index-finger $(id -un)\$" "$log" || fail "fprintd-enroll not called with the default finger for $(id -un): $(cat "$log")"
grep -q '^sudo' "$log" && fail "declining both stacks still ran sudo: $(cat "$log")"
grep -q 'pam_fprintd' "$root/etc/pam.d/sudo" && fail "declined, yet /etc/pam.d/sudo was edited"
[[ -e "$root/etc/pam.d/polkit-1" ]] && fail "declined, yet /etc/pam.d/polkit-1 was created"

# --finger reaches fprintd-enroll; a failed enrolment stops before any prompt.
: > "$log"
out="$(printf 'y\ny\n' | ENROLL_RC=1 setup --finger left-thumb 2>&1)"; rc=$?
[[ $rc -eq 1 ]] || fail "failed enrolment: want exit 1, got $rc"
grep -q "^fprintd-enroll -f left-thumb " "$log" || fail "--finger left-thumb did not reach fprintd-enroll: $(cat "$log")"
grep -q '^sudo' "$log" && fail "a failed enrolment still went on to edit PAM: $(cat "$log")"

# Enrol and accept both: the gate sits directly above pam_fprintd, both above
# the stack's first original auth line, polkit-1 starts from the vendor copy.
: > "$log"
out="$(printf 'y\ny\n' | setup 2>&1)"; rc=$?
[[ $rc -eq 0 ]] || fail "enrol + accept both: want exit 0, got $rc: $out"
check_stack() { # file
    local f="$1" lines
    mapfile -t lines < <(grep -nE '^auth[[:space:]]' "$f")
    [[ ${#lines[@]} -eq 3 ]] || { fail "$f: want 3 auth lines (gate, pam_fprintd, include), got ${#lines[@]}: $(cat "$f")"; return; }
    grep -qE '^[0-9]+:auth[[:space:]]+\[success=1 default=ignore\][[:space:]]+pam_exec\.so quiet /usr/bin/koompi-lid --closed$' <<< "${lines[0]}" \
        || fail "$f: first auth line is not the clamshell gate: ${lines[0]}"
    grep -qE '^[0-9]+:auth[[:space:]]+sufficient[[:space:]]+pam_fprintd\.so$' <<< "${lines[1]}" \
        || fail "$f: second auth line is not 'auth sufficient pam_fprintd.so': ${lines[1]}"
    grep -qE 'include[[:space:]]+system-auth$' <<< "${lines[2]}" || fail "$f: the original auth line is gone: ${lines[2]}"
    (( ${lines[0]%%:*} + 1 == ${lines[1]%%:*} )) || fail "$f: the gate is not directly above pam_fprintd"
    grep -q '^#%PAM-1.0' "$f" || fail "$f: lost its #%PAM-1.0 header"
}
check_stack "$root/etc/pam.d/sudo"
check_stack "$root/etc/pam.d/polkit-1"
grep -q '^password   include      system-auth$' "$root/etc/pam.d/polkit-1" || fail "polkit-1 was not started from the vendor file (/usr/lib/pam.d/polkit-1)"
grep -q '^sudo sed -i ' "$log" || fail "the PAM edits did not go through sudo: $(cat "$log")"
grep -q "^sudo install -m 644 $root/usr/lib/pam.d/polkit-1 $root/etc/pam.d/polkit-1\$" "$log" || fail "polkit-1 was not copied from the vendor file through sudo: $(cat "$log")"

# Idempotent: a second run leaves both files byte-identical.
cp "$root/etc/pam.d/sudo" "$WORK/sudo.1"; cp "$root/etc/pam.d/polkit-1" "$WORK/polkit.1"
out="$(printf 'y\ny\n' | PRINTS=1 setup 2>&1)" || fail "second run: want exit 0: $out"
cmp -s "$WORK/sudo.1" "$root/etc/pam.d/sudo" || fail "second run changed /etc/pam.d/sudo"
cmp -s "$WORK/polkit.1" "$root/etc/pam.d/polkit-1" || fail "second run changed /etc/pam.d/polkit-1"
grep -q 'already accepts' <<< "$out" || fail "second run should say the stacks are already set: $out"

# A stack with pam_fprintd added by hand (this machine's sudo) keeps its line
# and gets the gate directly above it.
printf '#%%PAM-1.0\nauth        sufficient  pam_fprintd.so\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\nsession\t\tinclude\t\tsystem-auth\n' > "$root/etc/pam.d/sudo"
printf 'y\nn\n' | setup > /dev/null 2>&1 || fail "gating a hand-written pam_fprintd line: want exit 0"
mapfile -t lines < <(grep -nE '^auth[[:space:]]' "$root/etc/pam.d/sudo")
[[ ${#lines[@]} -eq 3 ]] || fail "hand-written pam_fprintd: want 3 auth lines, got ${#lines[@]}"
grep -q 'koompi-lid --closed' <<< "${lines[0]}" || fail "hand-written pam_fprintd: gate not inserted above it"
grep -q 'sufficient  pam_fprintd.so' <<< "${lines[1]}" || fail "hand-written pam_fprintd line was replaced instead of kept"
[[ "$(grep -c 'pam_fprintd' "$root/etc/pam.d/sudo")" -eq 1 ]] || fail "hand-written pam_fprintd was duplicated"

# A stack whose module is gone but whose gate stayed gets exactly one of each.
printf '#%%PAM-1.0\nauth      [success=1 default=ignore]  pam_exec.so quiet /usr/bin/koompi-lid --closed\nauth\t\tinclude\t\tsystem-auth\n' > "$root/etc/pam.d/sudo"
printf 'y\nn\n' | setup > /dev/null 2>&1 || fail "stale gate: want exit 0"
[[ "$(grep -c 'koompi-lid --closed' "$root/etc/pam.d/sudo")" -eq 1 ]] || fail "stale gate was duplicated"
check_stack "$root/etc/pam.d/sudo"

# A stack with no auth line at all is left alone and reported.
printf '#%%PAM-1.0\naccount\t\tinclude\t\tsystem-auth\n' > "$root/etc/pam.d/sudo"
out="$(printf 'y\nn\n' | setup 2>&1)"; rc=$?
[[ $rc -eq 1 ]] || fail "no auth line: want exit 1, got $rc"
grep -q 'nothing was inserted' <<< "$out" || fail "no auth line: should say the file is unchanged: $out"
grep -q 'pam_fprintd' "$root/etc/pam.d/sudo" && fail "no auth line: the file was changed anyway"
echo "ok   setup: enrol for \$USER with --finger, y/N per stack, gate directly above pam_fprintd, idempotent, polkit-1 from the vendor file"

# --- the shell side ----------------------------------------------------------
first="$SHELL_ROOT/services/FirstRunExperience.qml"
body="$(awk '/function handleFirstRun/,/^    }/' "$first")"
grep -q 'execDetached(\["koompi-setup-fingerprint", "--invite"\])' <<< "$body" \
    || fail "handleFirstRun() no longer runs 'koompi-setup-fingerprint --invite'"
[[ "$(grep -c 'koompi-setup-fingerprint' "$first")" -eq 1 ]] || fail "FirstRunExperience should invoke the setup exactly once, on a first run"
section="$SHELL_ROOT/modules/settings/interface/LockScreenSection.qml"
grep -q 'command: \["koompi-hw-fingerprint"\]' "$section" || fail "LockScreenSection does not probe the reader with koompi-hw-fingerprint"
grep -q 'fprintd-list' "$section" || fail "LockScreenSection does not count enrolled prints with fprintd-list"
grep -q 'execDetached(\["koompi-setup-fingerprint", "--terminal"\])' "$section" || fail "LockScreenSection's button does not launch 'koompi-setup-fingerprint --terminal'"
grep -q 'Enrol fingerprint' "$section" || fail "LockScreenSection lost the 'Enrol fingerprint' button"
grep -q 'somehow use fingerprint' "$section" && fail "LockScreenSection still carries the placeholder tooltip"
for tool in koompi-hw-fingerprint koompi-setup-fingerprint; do
    grep -qE "^[[:space:]]+$tool\$" "$REPO_ROOT/sdata/dist-arch/koompi-shell/PKGBUILD" || fail "koompi-shell/PKGBUILD does not ship $tool"
done
echo "ok   shell: first run invites once, settings probe the reader and launch the setup in a terminal"

# /usr/bin/qmllint is Qt 5 and rejects list<var> and pragma ComponentBehavior
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    ln -s "$SHELL_ROOT" "$WORK/qs"
    for f in "$first" "$section"; do
        out="$("$QMLLINT" -I "$WORK" -I /usr/lib/qt6/qml "$f" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects ${f#"$SHELL_ROOT/"}"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in ${f#"$SHELL_ROOT/"}"; }
    done
    echo "ok   qmllint: FirstRunExperience and LockScreenSection parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

(( failed == 0 )) || exit 1
echo "fingerprint setup: all checks passed"
