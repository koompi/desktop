#!/usr/bin/env bash
# update_pull used `run git pull --ff-only`; answering "skip" at the failure
# prompt returns 0, so a network-failed update fell through to a before/after
# comparison and announced "already up to date". Pins: the pull's real outcome
# is what gets reported, in every direction.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v git >/dev/null || { echo "git not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export NO_COLOR=1
# Consumed by the sourced common.sh / update.sh, not by this file directly.
# shellcheck disable=SC2034
DRY_RUN=false
# shellcheck disable=SC2034
ASSUME_YES=false
# shellcheck source=../sdata/lib/common.sh
source "$ROOT/sdata/lib/common.sh"

git() { command git -c user.email=test@koompi -c user.name=test "$@"; }
export -f git

# A real remote with one commit, plus a clone that starts one commit behind.
remote="$T/remote.git"
seed="$T/seed"
git init -q --bare "$remote"
git clone -q "$remote" "$seed" 2>/dev/null
echo v1 > "$seed/file"
git -C "$seed" add . && git -C "$seed" commit -qm v1
git -C "$seed" push -q origin HEAD 2>/dev/null

work="$T/work"
git clone -q "$remote" "$work"
echo ahead > "$seed/file"
git -C "$seed" add . && git -C "$seed" commit -qm v2
git -C "$seed" push -q origin HEAD 2>/dev/null

# Consumed by the sourced update.sh, not by this file directly.
# shellcheck disable=SC2034
REPO_ROOT="$work"
# shellcheck source=../sdata/install/update.sh
source "$ROOT/sdata/install/update.sh"

out="$(update_pull < /dev/null 2>&1)"
grep -q 'updated ' <<<"$out" || fail "a real update was not reported as one: $out"
[[ "$(git -C "$work" rev-parse HEAD)" == "$(git -C "$seed" rev-parse HEAD)" ]] \
    || fail "the working repo did not actually move"

out="$(update_pull < /dev/null 2>&1)"
grep -q 'already up to date' <<<"$out" \
    || fail "a no-op pull is not reported as up to date: $out"

# The regression itself: a pull that cannot succeed must never read as current.
git -C "$work" reset -q --hard HEAD~1
git -C "$work" remote set-url origin "$T/no-such-remote.git"
before_head="$(git -C "$work" rev-parse HEAD)"
out="$(printf 's\n' | update_pull 2>&1)"
rc=$?
grep -qi 'not pulled' <<<"$out" \
    || fail "a skipped pull was not reported honestly: $out (rc=$rc)"
grep -q 'already up to date' <<<"$out" \
    && fail "a failed pull was reported as 'already up to date': $out"
[[ "$(git -C "$work" rev-parse HEAD)" == "$before_head" ]] \
    || fail "a skipped pull changed the checkout"

# Under --yes there is no skip to take: it must abort loudly instead of lying.
# shellcheck disable=SC2034
ASSUME_YES=true
out="$(update_pull < /dev/null 2>&1)"
rc=$?
[[ $rc -ne 0 ]] || fail "an unrecoverable pull failure exited 0 under --yes"
grep -q 'aborting' <<<"$out" || fail "the --yes abort said nothing useful: $out"

exit 0