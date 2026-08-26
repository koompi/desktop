#!/usr/bin/env bash
# J51: `koompi update` follows prod-hd, the line releases are cut from, but only
# where moving the branch takes nothing from anyone. Every other checkout - a
# dev's, a fork's, one with work in it - has to come out exactly as it went in.
# shellcheck source-path=SCRIPTDIR
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
pass() { printf 'PASS: %s\n' "$1"; }
command -v git >/dev/null || { echo "git not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export HOME="$T/home"
export NO_COLOR=1
mkdir -p "$HOME"
cat > "$HOME/.gitconfig" <<'GITCONFIG'
[user]
	name = koompi test
	email = test@koompi
[init]
	defaultBranch = main
[advice]
	detachedHead = false
	diverging = false
GITCONFIG

# Consumed by the sourced common.sh / update.sh, not by this file directly.
# shellcheck disable=SC2034
DRY_RUN=false
# shellcheck disable=SC2034
ASSUME_YES=false
# shellcheck source=../sdata/lib/common.sh disable=SC1091
source "$ROOT/sdata/lib/common.sh"
# Reassigned per case below; update.sh reads it at source time.
REPO_ROOT="$T"
# shellcheck source=../sdata/install/update.sh disable=SC1091
source "$ROOT/sdata/install/update.sh"

# An origin under a koompi/koompi-hd path so the "is this the KOOMPI repo?"
# check sees what it sees on a real machine. main is one commit ahead of
# prod-hd, the normal state: prod-hd is where main was last blessed.
new_origin() {
    local dir="$1" with_prod="$2" origin="$1/koompi/koompi-hd.git" seed="$1/seed"
    mkdir -p "$dir/koompi"
    git init -q --bare "$origin"
    git clone -q "$origin" "$seed" 2>/dev/null
    echo v1 > "$seed/file"; git -C "$seed" add .; git -C "$seed" commit -qm v1
    git -C "$seed" push -q origin HEAD:main
    echo v2 > "$seed/file"; git -C "$seed" add .; git -C "$seed" commit -qm v2
    git -C "$seed" push -q origin HEAD:main
    if [[ "$with_prod" == true ]]; then
        git -C "$seed" push -q origin "HEAD^:refs/heads/$PROD_BRANCH"
    fi
    printf '%s\n' "$origin"
}

# The remote moves prod-hd up to where main already is: the fast-forward-only
# promotion this whole scheme rests on.
promote_prod() {
    local origin="$1" seed="${1%/koompi/koompi-hd.git}/seed"
    git -C "$seed" push -q origin main:"refs/heads/$PROD_BRANCH"
}

branch_of()   { git -C "$1" rev-parse --abbrev-ref HEAD; }
head_of()     { git -C "$1" rev-parse HEAD; }
upstream_of() { git -C "$1" rev-parse --abbrev-ref '@{u}' 2>/dev/null; }
remote_head() { git -C "$1" ls-remote --heads origin "$2" | cut -f1; }

origin="$(new_origin "$T/a" true)"

# --- a managed checkout on main moves to prod-hd, and pulls it -----------------
work="$T/a/managed"
git clone -q "$origin" "$work"
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == "$PROD_BRANCH" ]] \
    || fail "a managed checkout did not move to $PROD_BRANCH: $out"
[[ "$(upstream_of "$work")" == "origin/$PROD_BRANCH" ]] \
    || fail "the moved branch does not track origin/$PROD_BRANCH: $(upstream_of "$work")"
[[ "$(head_of "$work")" == "$(remote_head "$work" "$PROD_BRANCH")" ]] \
    || fail "the moved checkout is not at origin/$PROD_BRANCH: $out"
grep -q "moved from 'main' to $PROD_BRANCH" <<<"$out" || fail "the move was not reported: $out"
pass "a managed checkout on main moves to $PROD_BRANCH"

# --- and once there it is an ordinary pull ------------------------------------
promote_prod "$origin"
out="$(update_pull < /dev/null 2>&1)"
grep -q 'updated ' <<<"$out" || fail "a checkout already on $PROD_BRANCH did not pull: $out"
grep -q 'moved from' <<<"$out" && fail "a checkout already on $PROD_BRANCH was moved again: $out"
[[ "$(head_of "$work")" == "$(remote_head "$work" "$PROD_BRANCH")" ]] \
    || fail "the pull did not land on origin/$PROD_BRANCH: $out"
pass "a checkout already on $PROD_BRANCH just pulls"

# --- a checkout with a commit of its own is not touched -----------------------
work="$T/a/local-commit"
git clone -q "$origin" "$work"
echo mine > "$work/mine"; git -C "$work" add .; git -C "$work" commit -qm mine
REPO_ROOT="$work"
before="$(head_of "$work")"
out="$(printf 'a\n' | update_pull 2>&1)"
[[ "$(branch_of "$work")" == main ]] || fail "a checkout with a local commit was moved: $out"
[[ "$(head_of "$work")" == "$before" ]] || fail "a checkout with a local commit moved its HEAD: $out"
grep -q 'commits upstream does not have' <<<"$out" || fail "no reason was given: $out"
pass "a checkout carrying its own commit is left alone"

# --- a dirty tree is not touched ----------------------------------------------
work="$T/a/dirty"
git clone -q "$origin" "$work"
echo edited >> "$work/file"
REPO_ROOT="$work"
before="$(head_of "$work")"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == main ]] || fail "a dirty checkout was moved: $out"
[[ "$(head_of "$work")" == "$before" ]] || fail "a dirty checkout moved its HEAD: $out"
[[ "$(cat "$work/file")" == "v2
edited" ]] || fail "a dirty checkout lost its edit: $(cat "$work/file")"
grep -q 'uncommitted changes' <<<"$out" || fail "no reason was given: $out"
pass "a dirty checkout is left alone"

# --- a developer's own branch, clean and pushed, is not touched ---------------
work="$T/a/feature"
git clone -q "$origin" "$work"
git -C "$work" checkout -q -b feature
git -C "$work" push -q -u origin feature 2>/dev/null
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == feature ]] || fail "a developer's branch was hijacked: $out"
grep -q "not main" <<<"$out" || fail "no reason was given: $out"
pass "a clean, fully pushed feature branch is left alone"

# --- a fork or a mirror is not touched ----------------------------------------
mkdir -p "$T/a/someone"
git clone -q --bare "$origin" "$T/a/someone/koompi-hd.git" 2>/dev/null
work="$T/a/fork"
git clone -q "$T/a/someone/koompi-hd.git" "$work"
git -C "$work" checkout -q main
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == main ]] || fail "a fork was moved onto $PROD_BRANCH: $out"
grep -q 'not the KOOMPI repo' <<<"$out" || fail "no reason was given: $out"
pass "a checkout whose origin is not the KOOMPI repo is left alone"

# --- the opt-out keeps a user on main, this run and every run -----------------
work="$T/a/optout"
git clone -q "$origin" "$work"
REPO_ROOT="$work"
out="$(KOOMPI_FOLLOW_PROD=0 update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == main ]] || fail "KOOMPI_FOLLOW_PROD=0 was ignored: $out"
grep -q 'switched off' <<<"$out" || fail "the opt-out said nothing: $out"
git -C "$work" config koompi.followprod false
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == main ]] || fail "koompi.followprod=false was ignored: $out"
out="$(KOOMPI_FOLLOW_PROD=1 update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == "$PROD_BRANCH" ]] \
    || fail "KOOMPI_FOLLOW_PROD=1 did not override the config: $out"
pass "the opt-out keeps a checkout on main until it is taken back"

# --- a dry run moves nothing ---------------------------------------------------
work="$T/a/dryrun"
git clone -q "$origin" "$work"
REPO_ROOT="$work"
before="$(head_of "$work")"
DRY_RUN=true
out="$(update_pull < /dev/null 2>&1)"
# shellcheck disable=SC2034
DRY_RUN=false
[[ "$(branch_of "$work")" == main ]] || fail "a dry run switched the branch: $out"
[[ "$(head_of "$work")" == "$before" ]] || fail "a dry run moved HEAD: $out"
grep -q 'dry run' <<<"$out" || fail "the dry run did not say what it would do: $out"
pass "a dry run moves nothing"

# --- no origin/prod-hd yet: today's behaviour, and not a word about it ---------
plain="$(new_origin "$T/b" false)"
work="$T/b/machine"
git clone -q "$plain" "$work"
git -C "$work" reset -q --keep HEAD~1     # a machine one commit behind main
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == main ]] || fail "a checkout moved with no $PROD_BRANCH to move to: $out"
[[ "$(head_of "$work")" == "$(remote_head "$work" main)" ]] \
    || fail "the ordinary update did not pull: $out"
grep -q 'updated ' <<<"$out" || fail "the ordinary update was not reported: $out"
grep -qi "$PROD_BRANCH" <<<"$out" \
    && fail "a machine with no $PROD_BRANCH upstream was told about it: $out"
grep -qiE '(^|[^a-z])(xx|error|fatal|warning|!!)' <<<"$out" \
    && fail "an ordinary update printed something that reads as a failure: $out"
pass "no origin/$PROD_BRANCH yet means an ordinary, silent update"

# --- the shape install.sh actually leaves behind: shallow, single-branch -------
shallow_origin="$(new_origin "$T/c" true)"
work="$T/c/shallow"
git clone -q --depth 1 --branch main "file://$shallow_origin" "$work" 2>/dev/null
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == "$PROD_BRANCH" ]] \
    || fail "a shallow single-branch checkout did not move: $out"
# prod-hd catches up to the commit the shallow clone was grafted at: the pull
# has to fast-forward across the parent the graft cut away.
promote_prod "$shallow_origin"
out="$(update_pull < /dev/null 2>&1)"
grep -q 'updated ' <<<"$out" \
    || fail "the pull after a shallow move did not fast-forward: $out"
[[ "$(head_of "$work")" == "$(remote_head "$work" "$PROD_BRANCH")" ]] \
    || fail "the shallow checkout is not at origin/$PROD_BRANCH: $out"
pass "a shallow single-branch checkout moves and keeps pulling"

# --- a local branch that only shares the name is not overwritten --------------
work="$T/a/own-prod"
git clone -q "$origin" "$work"
git -C "$work" checkout -q -b "$PROD_BRANCH"
echo mine > "$work/mine"; git -C "$work" add .; git -C "$work" commit -qm "my own $PROD_BRANCH"
git -C "$work" checkout -q main
# shellcheck disable=SC2034
REPO_ROOT="$work"
out="$(update_pull < /dev/null 2>&1)"
[[ "$(branch_of "$work")" == main ]] \
    || fail "a local $PROD_BRANCH that is not upstream's was checked out: $out"
grep -q "is not upstream's" <<<"$out" || fail "no reason was given: $out"
pass "a local $PROD_BRANCH branch of somebody's own is not taken over"


exit 0
