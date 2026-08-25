#!/usr/bin/env bash
# sync_tree used to run rsync inside a process substitution, which threw away
# its exit status and appended every printed path to the manifest regardless.
# A partial sync therefore ended in "config files installed" with a manifest
# claiming work that never happened - and uninstall would later delete files
# that were never replaced. Pins: a failed rsync fails the caller, and the
# manifest only ever records what a clean run wrote.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v rsync >/dev/null || { echo "rsync not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

export DRY_RUN=false ASSUME_YES=true NO_COLOR=1
export HOME="$T/home"
export XDG_STATE_HOME="$T/home/.local/state"
mkdir -p "$XDG_STATE_HOME"

# shellcheck source=../sdata/lib/common.sh
source "$ROOT/sdata/lib/common.sh"
# shellcheck source=../sdata/install/files.sh
source "$ROOT/sdata/install/files.sh"

src="$T/src"
dest="$T/dest"
mkdir -p "$src/sub" "$HOME/.config"
echo one > "$src/a"
echo two > "$src/b"
echo three > "$src/sub/c"

# Clean run: everything lands and only then reaches the manifest. rsync also
# reports the directories it created, and those are recorded too - the
# manifest is what uninstall walks, so it must include them.
sync_tree "$src" "$dest" || fail "a clean sync_tree reported failure"
for f in a b sub/c; do
    [[ -f "$dest/$f" ]] || fail "sync_tree did not copy $f"
done
expected="$(printf '%s\n' "$dest/a" "$dest/b" "$dest/sub" "$dest/sub/c" | sort)"
actual="$(sort "$MANIFEST")"
[[ "$actual" == "$expected" ]] || fail "the manifest is not exactly what was copied:
$actual"

# Failed run: the status must reach the caller and the manifest must not grow.
before="$(cat "$MANIFEST")"
out="$(sync_tree "$src" "$T/broken-dest" --this-is-not-an-rsync-flag 2>&1)"
rc=$?
[[ $rc -ne 0 ]] || fail "a failed rsync was reported as success: $out"
grep -q 'rsync failed' <<<"$out" || fail "the failure said nothing about rsync: $out"
[[ "$(cat "$MANIFEST")" == "$before" ]] \
    || fail "the manifest recorded paths from a sync that failed"

# The old shape cannot detect anything; make sure it stays gone.
grep -q '< <(rsync' "$ROOT/sdata/install/files.sh" \
    && fail "files.sh is back to running rsync in a process substitution, which discards its exit status"

exit 0