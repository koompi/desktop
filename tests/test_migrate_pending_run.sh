#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
MIGRATE="$ROOT/dots/.local/bin/koompi-migrate"

TEST_ROOT="$(mktemp -d)"
LOG="$TEST_ROOT/ran.log"
trap 'rm -rf "$TEST_ROOT"' EXIT

export KOOMPI_MIGRATE_MIGRATIONS_DIR="$TEST_ROOT/migrations"
export HOME="$TEST_ROOT/home"
mkdir -p "$KOOMPI_MIGRATE_MIGRATIONS_DIR" "$HOME"

printf 'echo ran-a >> %q\n' "$LOG" > "$KOOMPI_MIGRATE_MIGRATIONS_DIR/1000-a.sh"
printf 'echo ran-b >> %q\n' "$LOG" > "$KOOMPI_MIGRATE_MIGRATIONS_DIR/2000-b.sh"
chmod 644 "$KOOMPI_MIGRATE_MIGRATIONS_DIR"/*.sh

pending="$("$MIGRATE" --pending)"
[[ "$pending" == $'1000-a.sh\n2000-b.sh' ]] || { echo "unexpected pending list: $pending" >&2; exit 1; }

"$MIGRATE" run >/dev/null
[[ "$(cat "$LOG")" == $'ran-a\nran-b' ]] || { echo "migrations did not run in order" >&2; exit 1; }

MARKER_DIR="$HOME/.local/state/koompi/migrations"
[[ -f "$MARKER_DIR/1000-a.sh" && -f "$MARKER_DIR/2000-b.sh" ]] \
    || { echo "completion markers missing under $MARKER_DIR" >&2; exit 1; }

if "$MIGRATE" --pending >/dev/null; then
    echo "expected --pending to exit 1 once everything ran" >&2
    exit 1
fi

printf 'exit 1\n' > "$KOOMPI_MIGRATE_MIGRATIONS_DIR/3000-c.sh"
printf 'echo ran-d >> %q\n' "$LOG" > "$KOOMPI_MIGRATE_MIGRATIONS_DIR/4000-d.sh"
chmod 644 "$KOOMPI_MIGRATE_MIGRATIONS_DIR/3000-c.sh" "$KOOMPI_MIGRATE_MIGRATIONS_DIR/4000-d.sh"

if "$MIGRATE" run >/dev/null 2>&1; then
    echo "expected run to fail on migration 3000-c.sh" >&2
    exit 1
fi
[[ ! -e "$MARKER_DIR/3000-c.sh" ]] || { echo "a failed migration was marked complete" >&2; exit 1; }
[[ ! -e "$MARKER_DIR/4000-d.sh" ]] || { echo "a later migration ran after an earlier one failed" >&2; exit 1; }

printf 'migrate pending/run tests passed\n'
