#!/usr/bin/env bash
# Run every test in this directory.
#
# These are shell-level regression tests: each one shadows the commands that
# would touch the machine (pacman, makepkg, sudo, killall, hyprctl) and asserts
# on what the code under test tried to do. Nothing here installs, removes or
# stops anything, and nothing reads a password, so it is safe to run on the
# machine you are sitting at.
#
#   ./tests/run.sh
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
else
    C_RED=''; C_GREEN=''; C_BOLD=''; C_RST=''
fi

passed=0
failed=0
failures=()

for test in "$TESTS_DIR"/test_*.sh; do
    [[ -f "$test" ]] || continue
    name="$(basename -- "$test")"
    printf '%s==> %s%s\n' "${C_BOLD}" "$name" "${C_RST}"

    # Invoked through bash rather than executed, so a test that arrived without
    # its executable bit is still run instead of being reported as a failure.
    output="$(bash "$test" 2>&1 < /dev/null)"
    if [[ $? -eq 0 ]]; then
        printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RST}" "$name"
        passed=$((passed + 1))
    else
        printf '%s\n' "$output"
        printf '%s  xx%s %s\n' "${C_RED}" "${C_RST}" "$name"
        failed=$((failed + 1))
        failures+=("$name")
    fi
done

printf '\n%s%d passed, %d failed%s\n' "${C_BOLD}" "$passed" "$failed" "${C_RST}"
(( failed == 0 )) || {
    printf 'failed: %s\n' "${failures[*]}" >&2
    exit 1
}
