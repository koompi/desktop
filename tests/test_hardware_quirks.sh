#!/usr/bin/env bash
# The hardware quirk layer (OMARCHY-AUDIT O08): koompi-hw-match and
# koompi-hw-laptop read a fake DMI tree and lid directory, apply-hardware's
# dry run calls nothing, a real run under a fake root writes exactly the two
# generic quirks and is a no-op the second time, and every script in the layer
# passes shellcheck -x. Runs unprivileged: KOOMPI_HW_PREFIX redirects every
# path the quirks touch and drops the root requirement.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_ROOT/dots/.local/bin"
RUNNER="$REPO_ROOT/dots/.local/share/koompi/libexec/apply-hardware"
HW="$REPO_ROOT/sdata/hardware"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# Three machines. The desktop fixture carries a KOOMPI name so the match test
# has something to hit and something (ThinkPad) to miss.
dmi() {
    local dir="$tmp/dmi-$1"
    mkdir -p "$dir"
    printf '%s\n' "$2" > "$dir/product_name"
    printf '%s\n' "$3" > "$dir/product_family"
    printf '%s\n' "$4" > "$dir/chassis_type"
    printf '%s' "$dir"
}
lid_laptop="$(dmi lid 'KOOMPI E13' 'KOOMPI E' 3)"
chassis_laptop="$(dmi chassis 'KOOMPI M11' 'KOOMPI M' 10)"
desktop="$(dmi desktop 'KOOMPI Mini' 'KOOMPI Mini' 3)"
mkdir -p "$tmp/lid/LID0" "$tmp/nolid"
printf 'state:      open\n' > "$tmp/lid/LID0/state"

# 1. koompi-hw-laptop on the three fixtures.
KOOMPI_DMI_ROOT="$lid_laptop" KOOMPI_LID_DIR="$tmp/lid" "$BIN/koompi-hw-laptop" \
    || fail "a machine with a lid switch (chassis 3) is not a laptop"
KOOMPI_DMI_ROOT="$chassis_laptop" KOOMPI_LID_DIR="$tmp/nolid" "$BIN/koompi-hw-laptop" \
    || fail "chassis type 10 without a lid file is not a laptop"
KOOMPI_DMI_ROOT="$desktop" KOOMPI_LID_DIR="$tmp/nolid" "$BIN/koompi-hw-laptop" \
    && fail "a desktop (chassis 3, no lid) counts as a laptop"
KOOMPI_DMI_ROOT="$tmp/missing" KOOMPI_LID_DIR="$tmp/missing" "$BIN/koompi-hw-laptop" \
    && fail "no DMI and no lid directory counts as a laptop"
"$BIN/koompi-hw-laptop" extra 2>/dev/null; (( $? == 2 )) || fail "koompi-hw-laptop with an argument did not exit 2"

# 2. koompi-hw-match: product name, product family, case, miss, usage.
KOOMPI_DMI_ROOT="$desktop" "$BIN/koompi-hw-match" 'koompi mini' \
    || fail "product_name 'KOOMPI Mini' did not match 'koompi mini'"
KOOMPI_DMI_ROOT="$lid_laptop" "$BIN/koompi-hw-match" 'KOOMPI E$' \
    || fail "product_family 'KOOMPI E' did not match"
KOOMPI_DMI_ROOT="$lid_laptop" "$BIN/koompi-hw-match" 'ThinkPad' \
    && fail "'ThinkPad' matched a KOOMPI E13"
KOOMPI_DMI_ROOT="$tmp/missing" "$BIN/koompi-hw-match" 'KOOMPI' \
    && fail "a missing DMI tree matched"
"$BIN/koompi-hw-match" 2>/dev/null; (( $? == 2 )) || fail "koompi-hw-match without a pattern did not exit 2"
"$BIN/koompi-hw-match" '' 2>/dev/null; (( $? == 2 )) || fail "koompi-hw-match with an empty pattern did not exit 2"

# 3. A fake root with a kernel that ships hid_apple and NetworkManager installed.
prefix="$tmp/root"
mkdir -p "$prefix/usr/lib/modules/7.1.9-arch1-2/kernel/drivers/hid" \
         "$prefix/usr/lib/systemd/system"
: > "$prefix/usr/lib/modules/7.1.9-arch1-2/kernel/drivers/hid/hid-apple.ko.zst"
: > "$prefix/usr/lib/systemd/system/NetworkManager.service"

# Everything with a side effect that a quirk or the runner could reach
# (systemctl is-active is a query and stays real). Shimmed commands append
# their argv; a dry run must leave the log empty.
shim="$tmp/shim"
mkdir -p "$shim"
for cmd in nmcli modprobe tee install mv mkdir mktemp cp chmod; do
    cat > "$shim/$cmd" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$0 $*" >> "$SHIM_LOG"
SHIM
    chmod +x "$shim/$cmd"
done
export SHIM_LOG="$tmp/shim.log"

# 4. Dry run as the user on the laptop-by-lid fixture: lists both quirks as
#    "would", calls none of the shimmed commands, writes nothing, and ends on
#    the root note (Acceptance 2).
: > "$SHIM_LOG"
out="$(PATH="$shim:$PATH" KOOMPI_DMI_ROOT="$lid_laptop" KOOMPI_LID_DIR="$tmp/lid" \
       KOOMPI_HW_PREFIX="$prefix" KOOMPI_HW_LOG="$tmp/never.log" \
       "$RUNNER" --dry-run 2>&1)"
rc=$?
(( rc == 0 )) || fail "dry run exited $rc:
$out"
grep -q 'fix-fkeys.sh: would write: .*/etc/modprobe.d/hid_apple.conf' <<< "$out" \
    || fail "dry run did not list the hid_apple write:
$out"
grep -q 'wifi-powersave.sh: would write: .*/etc/NetworkManager/conf.d/koompi-wifi-powersave.conf' <<< "$out" \
    || fail "dry run did not list the wifi powersave write:
$out"
[[ -s "$SHIM_LOG" ]] && fail "dry run called something:
$(cat "$SHIM_LOG")"
[[ -e "$prefix/etc" ]] && fail "dry run created $prefix/etc"
[[ -e "$tmp/never.log" ]] && fail "dry run wrote the log file"
# The root note is for a user running against the real / (no prefix); the
# prefixed run above is allowed unprivileged and says so differently.
out="$(PATH="$shim:$PATH" KOOMPI_DMI_ROOT="$lid_laptop" KOOMPI_LID_DIR="$tmp/lid" \
       KOOMPI_HW_LOG="$tmp/never.log" "$RUNNER" --dry-run 2>&1)"
if (( EUID != 0 )); then
    grep -q 'root required to apply' <<< "$out" \
        || fail "an unprivileged dry run against / did not end on 'root required':
$out"
    err="$(KOOMPI_HW_LOG="$tmp/never.log" "$RUNNER" 2>&1 >/dev/null)"
    rc=$?
    (( rc == 1 )) && [[ "$err" == *"root required"* ]] \
        || fail "an unprivileged real run against / exited $rc with: $err"
fi
[[ -s "$SHIM_LOG" ]] && fail "dry run against / called something:
$(cat "$SHIM_LOG")"

# 5. Real run under the fake root: both files land, with the content the
#    quirks promise, and the decisions are in the log.
: > "$SHIM_LOG"
out="$(KOOMPI_DMI_ROOT="$lid_laptop" KOOMPI_LID_DIR="$tmp/lid" \
       KOOMPI_HW_PREFIX="$prefix" KOOMPI_HW_LOG="$tmp/hardware.log" \
       "$RUNNER" 2>&1)"
rc=$?
(( rc == 0 )) || fail "real run under the prefix exited $rc:
$out"
grep -qx 'options hid_apple fnmode=2' "$prefix/etc/modprobe.d/hid_apple.conf" 2>/dev/null \
    || fail "hid_apple.conf was not written with fnmode=2"
grep -qx 'wifi.powersave = 2' "$prefix/etc/NetworkManager/conf.d/koompi-wifi-powersave.conf" 2>/dev/null \
    || fail "koompi-wifi-powersave.conf was not written with wifi.powersave = 2"
grep -q '^\[connection\]$' "$prefix/etc/NetworkManager/conf.d/koompi-wifi-powersave.conf" 2>/dev/null \
    || fail "koompi-wifi-powersave.conf has no [connection] section"
grep -q 'fix-fkeys.sh: write: ' "$tmp/hardware.log" || fail "the log has no fix-fkeys decision"
grep -q 'wifi-powersave.sh: write: ' "$tmp/hardware.log" || fail "the log has no wifi-powersave decision"
grep -q '^[0-9]\{4\}-[0-9]\{2\}-[0-9]\{2\} [0-9:]\{8\} done$' "$tmp/hardware.log" || fail "the log has no timestamped 'done' line"
grep -q 'run: nmcli' <<< "$out" && fail "nmcli was called under a prefix (no daemon to reload)"
find "$prefix/etc" -name '.koompi-hw.*' | grep -q . && fail "a temp file from hw_write was left behind"

# 6. Second run: nothing to do, files untouched.
before="$(find "$prefix/etc" -type f -exec stat -c '%n %i %Y' {} + | sort)"
sleep 1
out="$(KOOMPI_DMI_ROOT="$lid_laptop" KOOMPI_LID_DIR="$tmp/lid" \
       KOOMPI_HW_PREFIX="$prefix" KOOMPI_HW_LOG="$tmp/hardware.log" \
       "$RUNNER" 2>&1)" || fail "second run failed:
$out"
after="$(find "$prefix/etc" -type f -exec stat -c '%n %i %Y' {} + | sort)"
[[ "$before" == "$after" ]] || fail "the second run rewrote a file:
$before
--
$after"
grep -q 'fix-fkeys.sh: not applied: .*exists' <<< "$out" \
    || fail "second run did not report hid_apple.conf as already present:
$out"
grep -q 'wifi-powersave.sh: not applied: .*already set' <<< "$out" \
    || fail "second run did not report the wifi conf as already set:
$out"

# 7. Desktop: wifi-powersave stays out; fix-fkeys still applies (an Apple-style
#    keyboard plugs into anything). A kernel without hid_apple: neither.
prefix2="$tmp/root2"
mkdir -p "$prefix2/usr/lib/modules/7.1.9-arch1-2/kernel/drivers/hid" "$prefix2/usr/lib/systemd/system"
: > "$prefix2/usr/lib/modules/7.1.9-arch1-2/kernel/drivers/hid/hid-apple.ko.zst"
: > "$prefix2/usr/lib/systemd/system/NetworkManager.service"
out="$(KOOMPI_DMI_ROOT="$desktop" KOOMPI_LID_DIR="$tmp/nolid" KOOMPI_HW_PREFIX="$prefix2" \
       KOOMPI_HW_LOG="$tmp/hardware2.log" "$RUNNER" 2>&1)" || fail "desktop run failed:
$out"
grep -q 'wifi-powersave.sh: not applied: not a laptop' <<< "$out" \
    || fail "wifi-powersave applied on a desktop:
$out"
[[ -e "$prefix2/etc/NetworkManager" ]] && fail "wifi-powersave wrote a file on a desktop"
[[ -f "$prefix2/etc/modprobe.d/hid_apple.conf" ]] || fail "fix-fkeys did not apply on a desktop with hid_apple"

prefix3="$tmp/root3"
mkdir -p "$prefix3/usr/lib/modules/7.1.9-arch1-2/kernel/drivers/hid"
out="$(KOOMPI_DMI_ROOT="$lid_laptop" KOOMPI_LID_DIR="$tmp/lid" KOOMPI_HW_PREFIX="$prefix3" \
       KOOMPI_HW_LOG="$tmp/hardware3.log" "$RUNNER" 2>&1)" || fail "no-module run failed:
$out"
grep -q 'fix-fkeys.sh: not applied: no installed kernel ships hid_apple' <<< "$out" \
    || fail "fix-fkeys applied without hid_apple on disk:
$out"
grep -q 'wifi-powersave.sh: not applied: NetworkManager is not installed' <<< "$out" \
    || fail "wifi-powersave applied without NetworkManager:
$out"
[[ -e "$prefix3/etc" ]] && fail "a quirk wrote under $prefix3 with every predicate false"

# 8. A failing quirk is reported, the rest still run, and the exit is 1.
hwdir="$tmp/hw"
cp -r "$HW/." "$hwdir/"
printf '#!/usr/bin/env bash\nset -euo pipefail\necho boom >&2\nexit 3\n' > "$hwdir/broken.sh"
printf 'run_quirk broken.sh\nrun_quirk fix-fkeys.sh\n' > "$hwdir/all.sh"
prefix4="$tmp/root4"
mkdir -p "$prefix4/usr/lib/modules/k/kernel/drivers/hid"
: > "$prefix4/usr/lib/modules/k/kernel/drivers/hid/hid-apple.ko"
out="$(KOOMPI_HARDWARE_DIR="$hwdir" KOOMPI_DMI_ROOT="$desktop" KOOMPI_LID_DIR="$tmp/nolid" \
       KOOMPI_HW_PREFIX="$prefix4" KOOMPI_HW_LOG="$tmp/hardware4.log" "$RUNNER" 2>&1)"
rc=$?
(( rc == 1 )) || fail "a failing quirk did not make the runner exit 1 (got $rc):
$out"
grep -q 'broken.sh: boom' <<< "$out" || fail "the failing quirk's output was not logged"
grep -q 'broken.sh: FAILED (exit 3)' <<< "$out" || fail "the failure line is missing"
[[ -f "$prefix4/etc/modprobe.d/hid_apple.conf" ]] || fail "a failing quirk stopped the quirks after it"

# 9. all.sh names only scripts that exist, and every script is shellcheck-clean
#    with -x (each sources lib.sh). The predicates and the runner too.
while read -r _ name; do
    [[ -f "$HW/$name" ]] || fail "all.sh runs $name, which does not exist under sdata/hardware"
done < <(grep -E '^run_quirk ' "$HW/all.sh")
if command -v shellcheck >/dev/null 2>&1; then
    mapfile -t scripts < <(find "$HW" -name '*.sh' | sort)
    scripts+=("$BIN/koompi-hw-match" "$BIN/koompi-hw-laptop" "$RUNNER")
    sc="$(cd "$REPO_ROOT" && shellcheck -x "${scripts[@]}" 2>&1)" \
        || fail "shellcheck -x:
$sc"
else
    echo "shellcheck not installed; skipping the lint half"
fi

(( failed == 0 )) || exit 1
printf 'hardware quirks: 3 fixtures, dry run clean, %d quirk scripts idempotent and lint-clean\n' \
    "$(grep -c '^run_quirk ' "$HW/all.sh")"
