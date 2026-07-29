#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=sdata/lib/arch.sh
source "$REPO_ROOT/sdata/lib/arch.sh"

calls="$(mktemp)"
trap 'rm -f "$calls"' EXIT

# Model pacman's important distinction:
#   pacman -Qq                  prints literal installed package names
#   pacman -Qq quickshell-git   resolves provides= and prints its provider
# shellcheck disable=SC2032  # The function is inherited by command substitutions in Bash.
pacman() {
    printf '%s\n' "$*" >> "$calls"
    if [[ "${PACMAN_FAIL:-false}" == true ]]; then
        return 1
    fi
    if [[ "$*" == "-Qq" ]]; then
        printf '%s\n' \
            illogical-impulse-quickshell-git \
            koompi-basic
        return 0
    fi
    if [[ "$*" == "-Qq quickshell-git" ]]; then
        printf '%s\n' illogical-impulse-quickshell-git
        return 0
    fi
    return 1
}

mapfile -t found < <(
    arch_exact_installed_packages \
        illogical-impulse-quickshell-git \
        quickshell-git \
        missing-package
)

[[ "${found[*]}" == "illogical-impulse-quickshell-git" ]] || {
    printf 'expected one exact stale package, got: %s\n' "${found[*]-<none>}" >&2
    exit 1
}
[[ "$(cat "$calls")" == "-Qq" ]] || {
    printf 'expected one untargeted package query, got:\n%s\n' "$(cat "$calls")" >&2
    exit 1
}

PACMAN_FAIL=true
if arch_exact_installed_packages quickshell-git >/dev/null 2>&1; then
    printf 'package database failure was treated as an empty installed set\n' >&2
    exit 1
fi

printf 'arch exact-package tests passed\n'
