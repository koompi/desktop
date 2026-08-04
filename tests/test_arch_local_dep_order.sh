#!/usr/bin/env bash
# A meta's depends[] are handed to yay, which knows the repos and the AUR and
# nothing else. So a dependency built from sdata/dist-arch has to be installed
# from its own PKGBUILD first, or the install dies on "No AUR package found" -
# which is exactly how ttf-koompi-star broke every Arch install on 2026-08-04.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$REPO_ROOT/sdata/dist-arch"

# The build order the installer actually uses, read from the recipe rather than
# restated here, so the two cannot drift.
mapfile -t order < <(
    sed -n '/^ARCH_DEP_PKGBUILDS=(/,/^)/p' "$DIST/install-deps.sh" |
        sed -e '1d' -e '$d' -e 's/#.*//' | tr -d ' \t' | grep -v '^$'
)
(( ${#order[@]} )) || { echo "could not read ARCH_DEP_PKGBUILDS" >&2; exit 1; }

# pkgname -> directory, for everything this repo can build.
declare -A built_by=()
for dir in "$DIST"/*/; do
    [[ -f "$dir/PKGBUILD" ]] || continue
    name="$(source "$dir/PKGBUILD" 2>/dev/null; printf '%s' "${pkgname:-}")"
    [[ -n "$name" ]] && built_by["$name"]="${dir%/}"
done

declare -A position=()
for i in "${!order[@]}"; do position["${order[$i]}"]="$i"; done

failed=0
for i in "${!order[@]}"; do
    entry="${order[$i]}"
    dir="$DIST/$entry"
    [[ -d "$dir" ]] || { echo "FAIL: $entry is listed but has no PKGBUILD dir" >&2; failed=1; continue; }

    mapfile -t deps < <(
        source "$dir/PKGBUILD" 2>/dev/null
        printf '%s\n' "${depends[@]:-}"
    )
    for dep in "${deps[@]}"; do
        # Strip any version constraint: yay is given the bare name either way.
        dep="${dep%%[<>=]*}"
        [[ -n "$dep" ]] || continue
        [[ -n "${built_by[$dep]:-}" ]] || continue          # repo or AUR, not ours
        if [[ -z "${position[$dep]:-}" ]]; then
            echo "FAIL: $entry depends on $dep, which this repo builds but the" >&2
            echo "      install order never installs - yay will look for it in the AUR" >&2
            failed=1
        elif (( position[$dep] > i )); then
            echo "FAIL: $entry depends on $dep, but $dep is built after it" >&2
            failed=1
        fi
    done
done

# The regression itself, named, so the test still means something if the loop
# above is ever loosened.
[[ -n "${position[ttf-koompi-star]:-}" ]] \
    || { echo "FAIL: ttf-koompi-star is not in the install order" >&2; failed=1; }

exit "$failed"
