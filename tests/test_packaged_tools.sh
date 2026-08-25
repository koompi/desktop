#!/usr/bin/env bash
# koompi-shell is the package that puts the koompi-* tools in /usr/bin on
# KOOMPI OS. Its install list is written by hand, and on 2026-08-25 it was five
# tools behind dots/.local/bin, so `koompi hook` and `koompi plugin` failed on
# every installed machine (OMARCHY-AUDIT O01). Pins the PKGBUILD's _tools and
# _tools_excluded arrays to the directory in both directions: a new tool has to
# be shipped or excluded with a reason, and a removed one cannot linger.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKGBUILD="$REPO_ROOT/sdata/dist-arch/koompi-shell/PKGBUILD"
BIN_DIR="$REPO_ROOT/dots/.local/bin"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

# Source the PKGBUILD in a subshell under set -u so a stray unbound variable
# is a failure here rather than a surprise inside makepkg. Only the top-level
# assignments run; build() and package() are defined, not called.
read_array() {
    # shellcheck disable=SC1090  # the PKGBUILD path is computed, not a literal
    ( set -u; source "$PKGBUILD" >/dev/null 2>&1 || exit 1
      declare -n arr="$1"; printf '%s\n' "${arr[@]}" )
}
mapfile -t shipped < <(read_array _tools) || true
mapfile -t excluded < <(read_array _tools_excluded) || true
(( ${#shipped[@]} )) || { echo "FAIL: could not read _tools from $PKGBUILD" >&2; exit 1; }
(( ${#excluded[@]} )) || { echo "FAIL: could not read _tools_excluded from $PKGBUILD" >&2; exit 1; }

# The array has to be what package() actually installs from, or it is decoration.
# shellcheck disable=SC2016  # the literal "${_tools[@]}" is the text being searched for
grep -q 'for tool in "\${_tools\[@\]}"' "$PKGBUILD" \
    || fail "package() does not install from \"\${_tools[@]}\""

declare -A listed=()
for name in "${shipped[@]}"; do
    [[ -x "$BIN_DIR/$name" ]] || fail "_tools lists $name but dots/.local/bin/$name is not an executable file"
    listed["$name"]=shipped
done
for name in "${excluded[@]}"; do
    [[ -e "$BIN_DIR/$name" ]] || fail "_tools_excluded lists $name but dots/.local/bin/$name does not exist (stale exclusion)"
    [[ -n "${listed[$name]:-}" ]] && fail "$name is in both _tools and _tools_excluded"
    listed["$name"]=excluded
    # The exclusion must carry its reason on the same line.
    grep -Eq "^[[:space:]]*${name}[[:space:]]+#[[:space:]]*[^[:space:]]" "$PKGBUILD" \
        || fail "_tools_excluded: $name has no comment saying why it is excluded"
done

for path in "$BIN_DIR"/koompi-*; do
    [[ -x "$path" ]] || continue
    name="$(basename -- "$path")"
    [[ -n "${listed[$name]:-}" ]] \
        || fail "dots/.local/bin/$name is neither in _tools nor in _tools_excluded in koompi-shell/PKGBUILD"
done

(( failed == 0 )) || exit 1
printf 'packaged tools: %d shipped, %d excluded, all accounted for\n' "${#shipped[@]}" "${#excluded[@]}"
