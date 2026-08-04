#!/usr/bin/env bash
# A persisted toggles array replaces the shipped default outright, so an install
# that first shipped six toggles keeps six forever - main screen and "All controls"
# showing the same six, which is what nady's machine did on 2026-08-04.
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export BACKUP_ROOT="$HOME/.koompi-dots-backup"
export DRY_RUN=false
export REPO_ROOT="$ROOT"
mkdir -p "$XDG_CONFIG_HOME/koompi"

# shellcheck source=sdata/lib/common.sh
source "$ROOT/sdata/lib/common.sh"
# shellcheck source=sdata/install/files.sh
source "$ROOT/sdata/install/files.sh"

CONFIG="$XDG_CONFIG_HOME/koompi/config.json"
MARKER="${KOOMPI_STATE_DIR}/migrations/quick-toggles-v1"

command -v jq >/dev/null || { echo "jq not installed; skipping" >&2; exit 0; }

fail() { echo "FAIL: $*" >&2; exit 1; }
types() { jq -r '.sidebar.quickToggles.android.toggles[].type' "$CONFIG"; }

# nady's shape: a short list, one entry at size 1 so it drew icon-only.
write_legacy_config() {
    rm -rf "$MARKER"
    cat > "$CONFIG" <<'EOF'
{
  "configVersion": 1,
  "sidebar": {
    "quickToggles": {
      "android": {
        "columns": 6,
        "toggles": [
          { "size": 2, "type": "network" },
          { "size": 2, "type": "bluetooth" },
          { "size": 1, "type": "idleInhibitor" },
          { "size": 2, "type": "mic" },
          { "size": 2, "type": "audio" },
          { "size": 2, "type": "nightLight" }
        ]
      }
    }
  }
}
EOF
}

# Called directly below, so the install path has to be checked separately or a
# dropped call site would still pass everything after this.
grep -q '^ *migrate_quick_toggles$' "$ROOT/sdata/install/files.sh" \
    || fail "install_files no longer calls migrate_quick_toggles"

write_legacy_config
migrate_quick_toggles

# Every type the shell ships is now reachable.
mapfile -t shipped < <(
    sed -n '/property list<var> toggles: \[/,/^ *\]/p' \
        "$ROOT/dots/.config/quickshell/koompi/modules/common/Config.qml" |
        grep -o '"type": *"[A-Za-z]*"' | sed 's/.*"\([A-Za-z]*\)"$/\1/'
)
(( ${#shipped[@]} > 6 )) || fail "read only ${#shipped[@]} shipped toggles from Config.qml"
for t in "${shipped[@]}"; do
    types | grep -Fxq "$t" || fail "$t is still missing after the migration"
done

# The drawer only earns its place if it holds more than the main screen's 3 rows.
count="$(types | wc -l)"
(( count > 6 )) || fail "list is still $count long; All controls would match the main screen"

# Their arrangement survives: same first six, same order, same sizes.
[[ "$(types | head -6 | tr '\n' ' ')" == "network bluetooth idleInhibitor mic audio nightLight " ]] \
    || fail "the user's existing order was not preserved"
[[ "$(jq -r '.sidebar.quickToggles.android.toggles[2].size' "$CONFIG")" == "1" ]] \
    || fail "an existing toggle's size was rewritten"

# Appended entries are size 2; size 1 is what drew an icon with no label.
jq -e '[.sidebar.quickToggles.android.toggles[6:][].size] | all(. == 2)' "$CONFIG" >/dev/null \
    || fail "an appended toggle is not size 2"

# Unrelated keys are untouched, and a backup exists.
[[ "$(jq -r '.configVersion' "$CONFIG")" == "1" ]] || fail "configVersion was lost"
[[ "$(jq -r '.sidebar.quickToggles.android.columns' "$CONFIG")" == "6" ]] || fail "columns was lost"
compgen -G "$BACKUP_ROOT/*/.config/koompi/config.json" >/dev/null || fail "no backup was written"

# Idempotent, and the marker stops a second pass re-reading the file at all.
before="$(cat "$CONFIG")"
migrate_quick_toggles
[[ "$(cat "$CONFIG")" == "$before" ]] || fail "a second run changed the config"
[[ -e "$MARKER" ]] || fail "no marker was written"

# A config already carrying the full list is left exactly as it was.
rm -f "$MARKER"
before="$(cat "$CONFIG")"
migrate_quick_toggles
[[ "$(cat "$CONFIG")" == "$before" ]] || fail "a complete config was rewritten"

# Malformed input is refused, not truncated.
rm -f "$MARKER"
printf 'not json' > "$CONFIG"
migrate_quick_toggles
[[ "$(cat "$CONFIG")" == "not json" ]] || fail "invalid JSON was not left untouched"

exit 0
