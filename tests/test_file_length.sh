#!/usr/bin/env bash
# The file-length cap from docs/conventions.md ("File and function length"),
# enforced as a ratchet. On 2026-08-25 the tree had 35 source files over cap,
# two of them past 1000 lines (AUDIT D3), and nothing stopped the next one.
# Every *.qml *.js *.lua *.sh *.zig *.rs in git, plus setup, install.sh and
# the tools in dots/.local/bin and dots/.local/share/koompi/libexec, is
# counted; vendored, generated and test trees are not. A file over its cap
# fails unless tests/file-length-allow.txt lists it with a line count, and a
# listed file that has grown past that count fails too, so the list can only
# shrink. Function length is review, not this test.
#
# Hooks for exercising the test itself:
#   FILE_LENGTH_FILES=<file>  one repo-relative path per line, used instead of
#                             `git ls-files`; the allow-list is only checked for
#                             the paths named
#   FILE_LENGTH_ROOT=<dir>    where those paths are read from (default: the repo)
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ROOT="${FILE_LENGTH_ROOT:-$REPO_ROOT}"
ALLOW="$REPO_ROOT/tests/file-length-allow.txt"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

# path -> cap, or nothing when the file is not one we measure.
cap_for() {
    case "/$1" in
        /installer/zig-pkg/*|*/translations/*|*/tests/*) return 1 ;;
    esac
    case "$1" in
        *.qml) echo 400 ;;
        *.js|*.lua) echo 300 ;;
        *.sh|setup|dots/.local/bin/*) echo 400 ;;  # install.sh is *.sh
        dots/.local/share/koompi/libexec/*) echo 400 ;;  # bash, no extension
        *.zig|*.rs) echo 600 ;;
        *) return 1 ;;
    esac
}

# wc -l does not count a last line without a newline; NR does.
count_lines() { awk 'END { print NR }' "$1"; }

# The allow-list: path<TAB>lines, C-sorted, one row per file, so a merge
# conflict in it is a real conflict and a duplicate cannot hide a growth.
[[ -f "$ALLOW" ]] || { echo "FAIL: missing $ALLOW" >&2; exit 1; }
declare -A allowed=()
while IFS= read -r row; do
    [[ "$row" =~ ^([^$'\t']+)$'\t'([0-9]+)$ ]] \
        || { fail "malformed allow-list row (want path<TAB>lines): '$row'"; continue; }
    path="${BASH_REMATCH[1]}"; lines="${BASH_REMATCH[2]}"
    [[ -z "${allowed[$path]:-}" ]] || fail "allow-list lists $path twice"
    cap="$(cap_for "$path")" || fail "allow-list lists $path, which is not a kind this test measures"
    allowed["$path"]="$lines"
done < "$ALLOW"
LC_ALL=C sort -c "$ALLOW" 2>/dev/null || fail "allow-list is not sorted (LC_ALL=C sort)"

if [[ -n "${FILE_LENGTH_FILES:-}" ]]; then
    mapfile -t files < "$FILE_LENGTH_FILES"
else
    mapfile -t files < <(git -C "$ROOT" ls-files)
fi
(( ${#files[@]} )) || { echo "FAIL: no files to measure under $ROOT" >&2; exit 1; }

declare -A seen=()
under=0
listed=0
for path in "${files[@]}"; do
    cap="$(cap_for "$path")" || continue
    [[ -f "$ROOT/$path" ]] || { fail "$path is in the file list but not on disk under $ROOT"; continue; }
    seen["$path"]=1
    lines="$(count_lines "$ROOT/$path")"
    if [[ -n "${allowed[$path]:-}" ]]; then
        listed=$((listed + 1))
        (( lines <= allowed[$path] )) \
            || fail "$path grew from ${allowed[$path]} to $lines lines; an allow-listed file may only shrink (tests/file-length-allow.txt)"
    elif (( lines > cap )); then
        fail "$path is $lines lines, cap is $cap; split it by concern (docs/conventions.md, File and function length)"
    else
        under=$((under + 1))
    fi
done

# A row for a file that is gone is a row that checks nothing.
if [[ -z "${FILE_LENGTH_FILES:-}" ]]; then
    for path in "${!allowed[@]}"; do
        [[ -n "${seen[$path]:-}" ]] || fail "allow-list row for $path, which is not in git; remove the row"
    done
fi

(( failed == 0 )) || exit 1
printf 'ok: %d files under cap, %d allow-listed and not grown\n' "$under" "$listed"
