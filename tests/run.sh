#!/usr/bin/env bash
# Run every test in this directory:  ./tests/run.sh
#
# Shell-level regression tests. Each shadows the commands that would touch the
# machine (pacman, makepkg, sudo, killall, hyprctl) and asserts on what the code
# tried to do, so nothing installs, removes, stops or reads a password.
#
# A test that cannot run here (no bun, no python-evdev, no live compositor) says
# so on a line containing "skipping" or starting with "skip:" and exits 0. It is
# counted as skipped, not passed, and its note is always printed, so a machine
# missing half the tools cannot report a green run that checked nothing. Only a
# non-zero exit fails the run.
set -uo pipefail

TESTS_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

if [[ -t 1 ]] && [[ -z "${NO_COLOR:-}" ]]; then
    C_RED=$'\e[31m'; C_GREEN=$'\e[32m'; C_YELLOW=$'\e[33m'; C_BOLD=$'\e[1m'; C_RST=$'\e[0m'
else
    C_RED=''; C_GREEN=''; C_YELLOW=''; C_BOLD=''; C_RST=''
fi

passed=0
skipped=0
failed=0
skips=()
failures=()

for test in "$TESTS_DIR"/test_*.sh; do
    [[ -f "$test" ]] || continue
    name="$(basename -- "$test")"
    printf '%s==> %s%s\n' "${C_BOLD}" "$name" "${C_RST}"

    # Invoked through bash rather than executed, so a test that arrived without
    # its executable bit is still run instead of being reported as a failure.
    output="$(bash "$test" 2>&1 < /dev/null)"
    rc=$?
    if (( rc != 0 )); then
        printf '%s\n' "$output"
        printf '%s  xx%s %s\n' "${C_RED}" "${C_RST}" "$name"
        failed=$((failed + 1))
        failures+=("$name")
    elif notes="$(grep -E 'skipping|^[[:space:]]*skip:' <<< "$output")"; then
        printf '%s\n' "$notes" | sed 's/^[[:space:]]*/      /'
        printf '%s  --%s %s (skipped)\n' "${C_YELLOW}" "${C_RST}" "$name"
        skipped=$((skipped + 1))
        skips+=("$name")
    else
        printf '%s  ok%s %s\n' "${C_GREEN}" "${C_RST}" "$name"
        passed=$((passed + 1))
    fi
done

printf '\n%s%d passed, %d skipped, %d failed%s\n' "${C_BOLD}" "$passed" "$skipped" "$failed" "${C_RST}"
(( skipped == 0 )) || printf 'skipped: %s\n' "${skips[*]}" >&2
(( failed == 0 )) || {
    printf 'failed: %s\n' "${failures[*]}" >&2
    exit 1
}
