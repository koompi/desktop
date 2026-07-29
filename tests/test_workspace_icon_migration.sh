#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT

export HOME="$TEST_ROOT/home"
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_STATE_HOME="$HOME/.local/state"
export BACKUP_ROOT="$HOME/.koompi-dots-backup"
export DRY_RUN=false
mkdir -p "$XDG_CONFIG_HOME/koompi"

# shellcheck source=sdata/lib/common.sh
source "$ROOT/sdata/lib/common.sh"
# shellcheck source=sdata/install/files.sh
source "$ROOT/sdata/install/files.sh"

CONFIG="$XDG_CONFIG_HOME/koompi/config.json"
MARKER="$XDG_STATE_HOME/koompi/migrations/workspace-app-icons-v1"

write_config() {
    local numbers="$1" icons="$2"
    jq -n \
        --argjson numbers "$numbers" \
        --argjson icons "$icons" \
        '{bar:{workspaces:{alwaysShowNumbers:$numbers,showAppIcons:$icons}},untouched:"keep-me"}' \
        > "$CONFIG"
}

assert_config() {
    local numbers="$1" icons="$2"
    jq -e \
        --argjson numbers "$numbers" \
        --argjson icons "$icons" \
        '.bar.workspaces.alwaysShowNumbers == $numbers
         and .bar.workspaces.showAppIcons == $icons
         and .untouched == "keep-me"' \
        "$CONFIG" >/dev/null
}

# Old installs can carry both flags. The one-time migration restores app icons
# and keeps every unrelated preference byte-for-byte equivalent as JSON data.
write_config true true
migrate_workspace_app_icons
assert_config false true
[[ -f "$MARKER" ]]
compgen -G "$BACKUP_ROOT/*/.config/koompi/config.json" >/dev/null

# Once migrated, a user may intentionally choose numbers again. Installer
# reruns must respect that choice.
write_config true true
migrate_workspace_app_icons
assert_config true true

# Configurations without the conflict are preserved and still marked complete.
rm -f "$MARKER"
write_config false false
migrate_workspace_app_icons
assert_config false false
[[ -f "$MARKER" ]]

# Invalid JSON must be left untouched and unmarked so a later repaired config
# can still receive the migration.
rm -f "$MARKER"
printf '{invalid\n' > "$CONFIG"
before="$(sha256sum "$CONFIG")"
migrate_workspace_app_icons
[[ "$(sha256sum "$CONFIG")" == "$before" ]]
[[ ! -e "$MARKER" ]]

# A dry run reports only. It changes neither config nor migration state.
write_config true true
DRY_RUN=true
before="$(sha256sum "$CONFIG")"
migrate_workspace_app_icons
[[ "$(sha256sum "$CONFIG")" == "$before" ]]
[[ ! -e "$MARKER" ]]

printf 'workspace icon migration tests passed\n'
