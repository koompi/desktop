#!/usr/bin/env bash
# A user's config.json is written in full at first run and never revisited, so
# a default changed later in Config.qml never reached anyone who already ran
# the shell (quickSliders.enable:false on the user's machine was exactly that).
# This pins the three-way merge contract and the dump it depends on:
#
#   user == old default, new differs -> adopt new
#   user != old default              -> keep the user's value
#   leaf new in defaults             -> add it
#
# plus: backup before write, temp+mv atomicity, and a defaults dump that is
# deterministic for a given tree.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$ROOT/dots/.local/share/koompi/libexec/update"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT

# The library guard defines every helper without running an update.
KOOMPI_UPDATE_LIBRARY=1 NO_COLOR=1
export KOOMPI_UPDATE_LIBRARY NO_COLOR
# shellcheck source=../dots/.local/share/koompi/libexec/update
source "$UPDATE"

merge() { cmd_merge_config "$T/old.json" "$T/new.json" "$T/user.json" 2>/dev/null; }

# --- 1. the canonical case ---------------------------------------------------
echo '{"a":1,"b":2}' > "$T/old.json"
echo '{"a":9,"b":5,"c":7}' > "$T/new.json"
echo '{"a":1,"b":3}' > "$T/user.json"
[[ "$(merge | jq -c .)" == '{"a":9,"b":3,"c":7}' ]] \
    || fail "canonical case broke: $(merge | jq -c .)"

# --- 2. nested objects, false defaults, user keys, removed defaults ----------
cat > "$T/old.json" <<'EOF'
{"bar":{"workspaces":{"showAppIcons":true,"alwaysShowNumbers":true}},
 "quickSliders":{"enable":false},"gone":5}
EOF
cat > "$T/new.json" <<'EOF'
{"bar":{"workspaces":{"showAppIcons":true,"alwaysShowNumbers":false}},
 "quickSliders":{"enable":true,"showMic":false}}
EOF
cat > "$T/user.json" <<'EOF'
{"bar":{"workspaces":{"showAppIcons":true,"alwaysShowNumbers":true}},
 "quickSliders":{"enable":false},"gone":5,"userOwn":{"z":9}}
EOF
merged="$(merge)"
[[ "$(echo "$merged" | jq '.bar.workspaces.alwaysShowNumbers')" == "false" ]] \
    || fail "an untouched default was not migrated to the new value"
[[ "$(echo "$merged" | jq '.quickSliders.enable')" == "true" ]] \
    || fail "a false default the user never changed was not adopted"
[[ "$(echo "$merged" | jq '.quickSliders.showMic')" == "false" ]] \
    || fail "a leaf new in the defaults was not added"
[[ "$(echo "$merged" | jq '.userOwn.z')" == "9" ]] \
    || fail "a key the user added beyond the defaults was dropped"
[[ "$(echo "$merged" | jq '.gone')" == "5" ]] \
    || fail "a key removed from the defaults was deleted from the user's config"

# A changed default must NOT override a value the user actually chose.
cat > "$T/old.json" <<'EOF'
{"bar":{"workspaces":{"alwaysShowNumbers":true}}}
EOF
cat > "$T/new.json" <<'EOF'
{"bar":{"workspaces":{"alwaysShowNumbers":false}}}
EOF
cat > "$T/user.json" <<'EOF'
{"bar":{"workspaces":{"alwaysShowNumbers":true}}}
EOF
[[ "$(merge | jq '.bar.workspaces.alwaysShowNumbers')" == "false" ]] \
    || fail "untouched true default did not follow the shipped change"
cat > "$T/user.json" <<'EOF'
{"bar":{"workspaces":{"alwaysShowNumbers":false}}}
EOF
[[ "$(merge | jq '.bar.workspaces.alwaysShowNumbers')" == "false" ]] \
    || fail "a value the user already moved to the new default was disturbed"
cat > "$T/user.json" <<'EOF'
{"bar":{"workspaces":{"alwaysShowNumbers":"user-chose-this"}}}
EOF
[[ "$(merge | jq -r '.bar.workspaces.alwaysShowNumbers')" == "user-chose-this" ]] \
    || fail "a customised value was overwritten by the new default"

# --- 3. apply mode: backup first, atomic write -------------------------------
cp "$T/old.json" "$T/cfg.json"
cmd_merge_config "$T/new.json" "$T/new2-does-not-exist" "$T/cfg.json" 2>&1 \
    && fail "apply accepted missing input"
compgen -G "$T/cfg.json.bak-*" >/dev/null && fail "a backup exists for a run that failed before merging"

echo '{"x":1}' > "$T/new.json"
cp "$T/old.json" "$T/cfg.json"
cmd_merge_config "$T/old.json" "$T/new.json" "$T/cfg.json" --apply >/dev/null 2>&1 \
    || fail "a clean apply failed"
compgen -G "$T/cfg.json.bak-*" >/dev/null || fail "no backup was written before applying"
[[ "$(jq '.x' "$T/cfg.json")" == "1" ]] || fail "the merged content was not written"
compgen -G "$T/.config-merge.*" >/dev/null && fail "a temp file survived a successful apply"

# A failed write leaves the original untouched, per the stop condition.
mkdir -p "$T/ro"
echo '{"keep":true}' > "$T/ro/cfg.json"
chmod 500 "$T/ro"
cmd_merge_config "$T/old.json" "$T/new.json" "$T/ro/cfg.json" --apply >/dev/null 2>&1 \
    && fail "a write into a read-only dir reported success"
[[ "$(jq -r '.keep' "$T/ro/cfg.json" 2>/dev/null)" == "true" ]] \
    || fail "the original config was damaged by a failed apply"
chmod 700 "$T/ro"
compgen -G "$T/ro/.config-merge.*" >/dev/null && fail "a temp file survived a failed apply"

# Invalid user JSON is refused, never rewritten.
printf 'not json' > "$T/broken.json"
before="$(cat "$T/broken.json")"
cmd_merge_config "$T/old.json" "$T/new.json" "$T/broken.json" --apply >/dev/null 2>&1 \
    && fail "invalid JSON was accepted"
[[ "$(cat "$T/broken.json")" == "$before" ]] || fail "invalid JSON was modified"

# --- 4. dumping real defaults from the tree ----------------------------------
if command -v qs >/dev/null 2>&1; then
    tree="$ROOT/dots/.config/quickshell/koompi"
    # -u: this test exports KOOMPI_UPDATE_LIBRARY=1 to source the helpers; the
    # subprocess must not inherit it or its main() would never run.
    dump_defaults() { env -u KOOMPI_UPDATE_LIBRARY bash "$ROOT/dots/.local/share/koompi/libexec/update" dump-defaults "$@"; }
    dump_defaults "$tree" "$T/dump-a.json" || fail "the defaults dump failed"
    jq -e 'type == "object"' "$T/dump-a.json" >/dev/null || fail "the dump is not a JSON object"
    [[ "$(jq '.sidebar.quickSliders.enable' "$T/dump-a.json")" == "false" ]] \
        || fail "the dump does not reflect Config.qml's shipped default"
    grep -q 'koompi-defaults\.' "$T/dump-a.json" \
        && fail "the dump leaks its sandbox path instead of a canonical placeholder"
    dump_defaults "$tree" "$T/dump-b.json" || fail "the second dump failed"
    cmp -s "$T/dump-a.json" "$T/dump-b.json" \
        || fail "two dumps of one tree differ; old-vs-new comparisons would lie"
else
    echo "qs not installed; skipping the dump smoke test" >&2
fi

exit 0