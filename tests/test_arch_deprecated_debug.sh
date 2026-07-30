#!/usr/bin/env bash
# The reported failure: `koompi update` died on
#   error: failed to commit transaction (conflicting files)
#   illogical-impulse-microtex-git-debug: /usr/lib/debug/... exists in filesystem
# because arch_drop_deprecated named the superseded packages but not the
# `-debug` split siblings makepkg produces alongside every one of them.
#
# The whole recipe is sourced with pacman shadowed, so this exercises the real
# sdata/dist-arch/install-deps.sh and touches no package.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sdata/lib/common.sh
source "$REPO_ROOT/sdata/lib/common.sh"

ASSUME_YES=true   # so run() never reads stdin

calls="$(mktemp)"
trap 'rm -f "$calls"' EXIT

# The one package that reproduces the report, plus a survivor that must not be
# touched and an unrelated package that is not in the stale list at all.
INSTALLED=(
    illogical-impulse-microtex-git-debug
    illogical-impulse-quickshell-git
    koompi-basic
    firefox
)

# shellcheck disable=SC2032  # inherited by command substitutions in Bash
pacman() {
    printf '%s\n' "$*" >> "$calls"
    case "$1" in
        -Qq)
            # Untargeted: the literal installed-name list.
            [[ $# -eq 1 ]] && { printf '%s\n' "${INSTALLED[@]}"; return 0; }
            # Targeted: only the plasma-browser-integration probe reaches here,
            # and answering "installed" keeps the recipe from asking anything.
            return 0
            ;;
        -Q)  printf '%s 999-999\n' "$2"; return 0 ;;   # every meta is current
        -T)  return 0 ;;                               # every depends[] is satisfied
        -Rdd) return 0 ;;
    esac
    return 0
}
# shellcheck disable=SC2032
sudo() { "$@"; }

# shellcheck source=sdata/dist-arch/install-deps.sh
source "$REPO_ROOT/sdata/dist-arch/install-deps.sh" || {
    printf 'the dependency recipe failed against the stubbed pacman\n' >&2
    exit 1
}

removal="$(grep -m1 '^-Rdd' -- "$calls")" || {
    printf 'no pacman -Rdd call was made; the stale -debug package was left installed\n' >&2
    printf 'calls were:\n%s\n' "$(cat "$calls")" >&2
    exit 1
}

for expected in illogical-impulse-microtex-git-debug illogical-impulse-quickshell-git; do
    grep -qw -- "$expected" <<< "$removal" || {
        printf 'removal did not include %s\n  got: %s\n' "$expected" "$removal" >&2
        exit 1
    }
done

# A -debug name that is not installed must not be passed to pacman, or the
# whole removal fails with "target not found".
for unexpected in illogical-impulse-quickshell-git-debug koompi-basic firefox; do
    grep -qw -- "$unexpected" <<< "$removal" && {
        printf 'removal included %s, which is not installed\n  got: %s\n' "$unexpected" "$removal" >&2
        exit 1
    }
done

printf 'arch deprecated -debug removal test passed\n'
