#!/usr/bin/env bash
# koompi-factory-reset rolls the root subvolume back to @baseline and deletes
# every human account. Getting it wrong bricks a school laptop, so nothing here
# reaches a real binary: PATH is rebuilt from scratch with shims for snapper,
# userdel, id, getent, btrfs, findmnt and loginctl plus symlinks to only the
# text utilities the scripts parse with, so a call to anything unshimmed fails
# with "command not found" instead of touching this machine.
#
# Pins, in order of how much damage each miss would do:
#   - a system account or root never appears in any userdel call
#   - the real run needs the word typed on a tty, and one wrong word changes nothing
#   - it refuses rather than half-resetting: no snapper, no @baseline, not root,
#     an account still logged in, no way to log in afterwards, and a @baseline
#     that still carries the previous owner's accounts
#   - --dry-run lists exactly the human accounts and calls nothing
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
RESET="$ROOT/dots/.local/bin/koompi-factory-reset"

passed=0
failed=0
pass() { printf 'PASS: %s\n' "$1"; passed=$((passed + 1)); }
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=$((failed + 1)); }
check() { if [[ "$2" == "$3" ]]; then pass "$1"; else fail "$1 (got '$2', wanted '$3')"; fi; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# ---------------------------------------------------------------- shims -----

mkdir -p "$T/bin" "$T/bin-nosnapper" "$T/real" "$T/log"

# Only the text utilities koompi-factory-reset and koompi-snapshot parse with.
# Everything else - snapper, userdel, btrfs, findmnt, loginctl, getent, id - can
# only be reached through a shim, so an unstubbed call is a hard failure.
for b in bash grep dirname readlink awk cut tr sort cat sed; do
    real="$(command -v "$b")" || { echo "no $b on this machine; skipping" >&2; exit 0; }
    ln -sf "$real" "$T/real/$b"
done

write_shim() {
    local name="$1"
    cat > "$T/bin/$name"
    chmod +x "$T/bin/$name"
    cp "$T/bin/$name" "$T/bin-nosnapper/$name"
}

write_shim id <<SHIM
#!/usr/bin/env bash
[[ "\${1:-}" == "-u" ]] && { echo "\${FAKE_UID:-0}"; exit 0; }
echo "id shim: unexpected args \$*" >&2; exit 1
SHIM

write_shim findmnt <<SHIM
#!/usr/bin/env bash
echo "\${FAKE_FSTYPE:-btrfs}"
SHIM

write_shim btrfs <<SHIM
#!/usr/bin/env bash
[[ "\${1:-}" == "subvolume" && "\${2:-}" == "show" ]] || { echo "btrfs shim: unexpected args \$*" >&2; exit 1; }
echo "@home"
SHIM

write_shim loginctl <<SHIM
#!/usr/bin/env bash
[[ "\${1:-}" == "list-users" ]] || { echo "loginctl shim: unexpected args \$*" >&2; exit 1; }
for u in \${LOGGED_IN:-}; do echo "1001 \$u"; done
SHIM

write_shim getent <<SHIM
#!/usr/bin/env bash
case "\${1:-}" in
    passwd) cat "\$LIVE/etc/passwd" ;;
    group)  [[ -n "\${2:-}" ]] && grep "^\${2}:" "\$LIVE/etc/group" || cat "\$LIVE/etc/group" ;;
    *) echo "getent shim: unexpected database '\${1:-}'" >&2; exit 1 ;;
esac
SHIM

write_shim userdel <<SHIM
#!/usr/bin/env bash
printf 'userdel %s\n' "\$*" >> "$T/log/calls"
SHIM

# snapper deliberately absent from bin-nosnapper: the "no snapper" refusal has
# to see a machine where the binary genuinely is not there.
cat > "$T/bin/snapper" <<SHIM
#!/usr/bin/env bash
printf 'snapper %s\n' "\$*" >> "$T/log/calls"
if [[ "\${1:-}" == "list-configs" ]]; then
    printf 'Config | Subvolume\n-------+----------\nroot   | /\n'
    exit 0
fi
if [[ "\${1:-}" == "-c" && "\${2:-}" == "root" && "\${3:-}" == "list" ]]; then
    cat "\$SNAPPER_LIST"
    exit 0
fi
if [[ "\${1:-}" == "-c" && "\${2:-}" == "root" && "\${3:-}" == "rollback" ]]; then
    exit 0
fi
echo "snapper shim: unexpected args \$*" >&2
exit 1
SHIM
chmod +x "$T/bin/snapper"

# --------------------------------------------------------------- fixtures ---

# The live machine: root, two system accounts, nobody, and two students. Only
# student1 and guest may ever be named in a userdel call.
mkdir -p "$T/live/etc"
cat > "$T/live/etc/passwd" <<'EOF'
root:x:0:0::/root:/bin/bash
bin:x:1:1::/:/usr/bin/nologin
sysbot:x:400:400::/var/lib/sysbot:/usr/bin/nologin
nobody:x:65534:65534:Nobody:/:/usr/bin/nologin
student1:x:1001:1001::/home/student1:/bin/bash
guest:x:1002:1002::/home/guest:/bin/bash
EOF
cat > "$T/live/etc/group" <<'EOF'
root:x:0:
sysbot:x:400:
wheel:x:998:student1
EOF

# The @baseline tree the rollback would restore, at snapshot 4.
# kind=oem     : no human account, first-boot provisioning armed  -> the reset runs
# kind=unarmed : no human account, nothing arms user creation     -> no way back in
# kind=stock   : what a real KOOMPI install pins - the first owner's account is
#                already inside @baseline, because archinstall creates the user
#                before post_install.sh takes the snapshot
make_baseline() {
    local kind="$1"
    local dir="$T/roots/$kind"
    local snap="$dir/.snapshots/4/snapshot"
    mkdir -p "$snap/etc" "$snap/usr/bin" "$snap/etc/systemd/system/multi-user.target.wants"
    cat > "$snap/etc/passwd" <<'EOF'
root:x:0:0::/root:/bin/bash
bin:x:1:1::/:/usr/bin/nologin
nobody:x:65534:65534:Nobody:/:/usr/bin/nologin
EOF
    printf 'root:x:0:\nwheel:x:998:\n' > "$snap/etc/group"
    printf 'root:!:19000::::::\n' > "$snap/etc/shadow"
    : > "$snap/etc/machine-id"
    if [[ "$kind" == "stock" ]]; then
        printf 'student1:x:1001:1001::/home/student1:/bin/bash\n' >> "$snap/etc/passwd"
        # shellcheck disable=SC2016  # a literal crypt(3) hash, nothing to expand
        printf 'student1:$6$installtime$hash:19000::::::\n' >> "$snap/etc/shadow"
        sed -i 's/^wheel:x:998:/wheel:x:998:student1/' "$snap/etc/group"
        printf 'e4f1c0d2b3a4956871234567890abcde\n' > "$snap/etc/machine-id"
    fi
    if [[ "$kind" != "stock" ]]; then
        printf '#!/bin/sh\n' > "$snap/usr/bin/koompi-oem-provision"
        chmod +x "$snap/usr/bin/koompi-oem-provision"
    fi
    if [[ "$kind" == "oem" ]]; then
        : > "$snap/etc/systemd/system/multi-user.target.wants/koompi-oem-provision.service"
    fi
    printf '%s\n' "$dir"
}
mkdir -p "$T/roots"
for k in oem unarmed stock; do make_baseline "$k" >/dev/null; done

# snapper's own list output, box-drawing separators and all - the number of the
# @baseline snapshot has to be read out of this, never guessed.
cat > "$T/list-with-baseline" <<'EOF'
 # │ Description                            │ Userdata
---┼----------------------------------------┼--------------------------
 0 │ current                                │
 4 │ KOOMPI @baseline (factory reset point) │ important=yes,baseline=yes
 9 │ pre-update 2026-08-20T09:00:00+07:00   │ important=no
EOF
cat > "$T/list-without-baseline" <<'EOF'
 # │ Description                          │ Userdata
---┼--------------------------------------┼--------------
 0 │ current                              │
 9 │ pre-update 2026-08-20T09:00:00+07:00 │ important=no
EOF

# ---------------------------------------------------------------- harness ---

# Runs the tool with a PATH that contains nothing but the shims and the text
# utilities. OUT and RC are the result; "$T/log/calls" is every shimmed call.
OUT=""; RC=0
run_reset() {
    local bindir="$T/bin"
    [[ "${NO_SNAPPER:-0}" == "1" ]] && bindir="$T/bin-nosnapper"
    : > "$T/log/calls"
    OUT="$(PATH="$bindir:$T/real" \
        LIVE="$T/live" \
        SNAPPER_LIST="${SNAPPER_LIST:-$T/list-with-baseline}" \
        KOOMPI_RESET_ROOT="${BASELINE_ROOT:-$T/roots/oem}" \
        KOOMPI_RESET_TTY="${TTY_FILE:-/dev/null}" \
        FAKE_UID="${FAKE_UID:-0}" \
        FAKE_FSTYPE="${FAKE_FSTYPE:-btrfs}" \
        LOGGED_IN="${LOGGED_IN:-}" \
        bash "$RESET" "$@" 2>&1)"
    RC=$?
}

# Assertion vocabulary. `has` reads the tool's output, `did` reads the log of
# every shimmed call, and want/wantnot turn either into one PASS or FAIL line
# that carries the evidence.
has() { grep -Eq -- "$1" <<<"$OUT"; }
did() { grep -Eq -- "$1" "$T/log/calls"; }
touched_anything() { grep -Eq 'userdel|rollback' "$T/log/calls"; }
calls() { cat "$T/log/calls" 2>/dev/null; }
want() {
    local m="$1"; shift
    if "$@"; then pass "$m"; else fail "$m
  output: $OUT
  calls:  $(calls)"; fi
}
wantnot() {
    local m="$1"; shift
    if "$@"; then fail "$m
  output: $OUT
  calls:  $(calls)"; else pass "$m"; fi
}
count() { grep -c -- "$1" "$T/log/calls" 2>/dev/null; }

# Hook for reproducing a run by hand (and for pasting real output into a report):
#   KOOMPI_RESET_DEMO=oem bash tests/test_factory_reset.sh --dry-run
# builds the same shims and fixtures, runs the tool once with the given arguments
# and exits with its status. KOOMPI_RESET_DEMO picks the @baseline fixture (oem,
# unarmed or stock); NO_SNAPPER, SNAPPER_LIST and FAKE_UID work as they do above.
if [[ -n "${KOOMPI_RESET_DEMO:-}" ]]; then
    BASELINE_ROOT="$T/roots/$KOOMPI_RESET_DEMO" run_reset "$@"
    printf '%s\n' "$OUT"
    exit "$RC"
fi

# ------------------------------------------------------------------ cases ---

# --help must work before any guard, so someone can read what it does without
# being root on a btrfs machine.
FAKE_UID=1000 run_reset --help
check "--help exits 0 without root" "$RC" "0"
want "--help documents the modes and the refusal codes" has -- '--dry-run'
want "--help lists the exit codes" has 'Exit codes'

# Guard 1: root.
FAKE_UID=1000 run_reset --dry-run
check "not root refuses non-zero" "$RC" "4"
want "the not-root refusal says so and names sudo" has 'must run as root; try: sudo'

# Guard 2: btrfs.
FAKE_FSTYPE=ext4 run_reset --dry-run
check "a non-btrfs root refuses non-zero" "$RC" "4"
want "the non-btrfs refusal says why" has 'not btrfs'

# Guard 3: snapper. A factory reset that silently does nothing is worse than an
# error, so unlike koompi-snapshot this must NOT exit 0.
NO_SNAPPER=1 run_reset --dry-run
check "no snapper refuses non-zero (not koompi-snapshot's exit 0)" "$RC" "4"
want "the no-snapper refusal names snapper" has 'snapper is not installed'

# Guard 4: a pinned @baseline. Never fall back to some other snapshot number.
SNAPPER_LIST="$T/list-without-baseline" run_reset --dry-run
check "no @baseline refuses non-zero" "$RC" "4"
want "the no-baseline refusal names @baseline" has 'no @baseline snapshot'
wantnot "no rollback was staged without a baseline" did 'rollback'

# --dry-run: the plan, and nothing else.
run_reset --dry-run
check "--dry-run exits 0 on a resettable machine" "$RC" "0"
want "--dry-run lists student1" has 'userdel -r student1'
want "--dry-run lists guest" has 'userdel -r guest'
want "--dry-run names student1's home directory" has '/home/student1'
want "--dry-run names guest's home directory" has '/home/guest'
wantnot "--dry-run plans no system account and no root" \
    has '(^| )[0-9]*\.? ?userdel -r (root|bin|sysbot|nobody)( |$)'
want "--dry-run names the baseline snapshot number it read from snapper" has 'rollback 4'
want "--dry-run shows the reboot step" has 'reboot'
want "--dry-run says what @baseline puts back" has '@baseline puts back'
wantnot "--dry-run changed nothing: no userdel, no rollback" touched_anything

# No arguments is the dry run, so the destructive mode can only be asked for.
run_reset
check "no arguments is the dry run" "$RC" "0"
wantnot "a bare invocation changed nothing" touched_anything

# --apply without the word: the plan is printed and nothing happens.
printf 'yes\n' > "$T/tty-wrong"
TTY_FILE="$T/tty-wrong" run_reset --apply
check "--apply with the wrong word refuses non-zero" "$RC" "5"
want "the declined run says nothing was changed" has 'nothing was changed'
wantnot "a wrong confirmation word changed nothing" touched_anything

# --apply with the word typed on the tty: the real sequence, exactly once each.
printf 'RESET\n' > "$T/tty-right"
TTY_FILE="$T/tty-right" run_reset --apply
check "--apply with the typed word exits 0" "$RC" "0"
check "userdel -r student1 ran exactly once" "$(count '^userdel -r student1$')" "1"
check "userdel -r guest ran exactly once" "$(count '^userdel -r guest$')" "1"
check "userdel ran only for the two human accounts" "$(count '^userdel ')" "2"
check "the rollback was staged exactly once" "$(count 'rollback 4')" "1"
wantnot "no system account and no root reached userdel" \
    did '^userdel .*\b(root|bin|sysbot|nobody)\b'
wantnot "no system UID appears in any call" did '^userdel .*\b(0|1|400|65534)\b'
want "the real run prints the reboot instruction" has 'systemctl reboot'
wantnot "the tool never called reboot itself" did '(^| )reboot( |$)'

# The order matters: every account has to be gone before the rollback is staged,
# because the rollback is what the next boot acts on.
first_rollback="$(grep -n 'rollback' "$T/log/calls" | head -1 | cut -d: -f1)"
last_userdel="$(grep -n '^userdel ' "$T/log/calls" | tail -1 | cut -d: -f1)"
if [[ -n "$first_rollback" && -n "$last_userdel" ]] && (( last_userdel < first_rollback )); then
    pass "every userdel ran before the rollback was staged"
else
    fail "the rollback was staged before the accounts were removed: $(calls)"
fi

# An open session makes userdel -r fail halfway, which is the one state this
# tool must never produce.
LOGGED_IN="student1" TTY_FILE="$T/tty-right" run_reset --apply
check "a logged-in account in the plan refuses non-zero" "$RC" "6"
wantnot "the logged-in refusal happened before anything was removed" touched_anything

# Do 5: every wheel administrator is in the plan and nothing re-creates one.
BASELINE_ROOT="$T/roots/unarmed" TTY_FILE="$T/tty-right" run_reset --apply
check "the last-admin refusal exits non-zero" "$RC" "2"
want "the last-admin refusal explains that nobody could log in" \
    has 'leave nobody able to get an account'
want "the last-admin refusal names the wheel account it would remove" has 'student1'
wantnot "the last-admin refusal changed nothing" touched_anything

# What a real KOOMPI install actually looks like: @baseline was pinned after
# archinstall created the first user, so rolling back restores that account and
# its password. Handing that to the next student is not a factory reset.
BASELINE_ROOT="$T/roots/stock" TTY_FILE="$T/tty-right" run_reset --apply
check "a @baseline carrying the previous owner's account refuses non-zero" "$RC" "3"
want "the non-pristine refusal says @baseline is not pristine" has 'not a pristine image'
want "the non-pristine refusal names the account @baseline would restore" has 'student1'
wantnot "the non-pristine refusal changed nothing" touched_anything

# An unknown flag must not be read as a mode.
run_reset --yes
check "an unknown argument is a usage error" "$RC" "1"
wantnot "--yes is not a confirmation path" touched_anything

printf '\n%d passed, %d failed\n' "$passed" "$failed"
(( failed == 0 )) || exit 1
