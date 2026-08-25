#!/usr/bin/env bash
# run.sh used to count a test that exited 0 with a "skipping" note as passed and
# hide the note, so on a machine without bun/node/python-evdev around fifteen
# tests went green while checking nothing (BUG-AUDIT M4). Runs a copy of run.sh
# over three stand-in tests (one passes, one skips, one fails) and checks the
# three counts, that the skip note is shown, and that only a failure makes the
# run exit non-zero.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cp "$TESTS_DIR/run.sh" "$tmp/run.sh"
printf '#!/usr/bin/env bash\necho "ok: fine"\n' > "$tmp/test_a_pass.sh"
printf '#!/usr/bin/env bash\necho "bun not installed; skipping" >&2\nexit 0\n' > "$tmp/test_b_skip.sh"
printf '#!/usr/bin/env bash\necho "FAIL: broken" >&2\nexit 1\n' > "$tmp/test_c_fail.sh"

out="$(NO_COLOR=1 bash "$tmp/run.sh" 2>&1)"
rc=$?
(( rc == 1 )) || fail "with one failing test run.sh exited $rc, wanted 1"
grep -qx '1 passed, 1 skipped, 1 failed' <<< "$out" \
    || fail "summary is not '1 passed, 1 skipped, 1 failed':
$out"
grep -q 'bun not installed; skipping' <<< "$out" \
    || fail "the skip note was not printed"
grep -q -- '-- test_b_skip.sh (skipped)' <<< "$out" \
    || fail "the skipped test is not marked as skipped"
grep -q 'skipped: test_b_skip.sh' <<< "$out" \
    || fail "the skipped test is not listed at the end"
grep -q 'failed: test_c_fail.sh' <<< "$out" \
    || fail "the failing test is not listed at the end"

# A skip alone keeps the run green: only a failure changes the exit status.
rm -f "$tmp/test_c_fail.sh"
out="$(NO_COLOR=1 bash "$tmp/run.sh" 2>&1)"
rc=$?
(( rc == 0 )) || fail "with only a pass and a skip run.sh exited $rc, wanted 0"
grep -qx '1 passed, 1 skipped, 0 failed' <<< "$out" \
    || fail "summary is not '1 passed, 1 skipped, 0 failed':
$out"

# The other spelling: a "skip:" line, as test_globalmenu.sh and friends print.
printf '#!/usr/bin/env bash\nprintf "skip: no cargo; nothing built\\n"\n' > "$tmp/test_d_skip.sh"
out="$(NO_COLOR=1 bash "$tmp/run.sh" 2>&1)"
grep -qx '1 passed, 2 skipped, 0 failed' <<< "$out" \
    || fail "a 'skip:' line is not counted as a skip:
$out"

(( failed == 0 )) || exit 1
echo "ok: run.sh reports passed, skipped and failed separately and exits non-zero only on a failure"
