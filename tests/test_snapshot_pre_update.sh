#!/usr/bin/env bash
# koompi-snapshot --pre-update used to prune the pacman cache BEFORE creating
# the snapper snapshot, under set -e. /var/cache/pacman/pkg is root-owned, so
# unprivileged paccache exits 1 and the script aborted before snapper ran:
# every packaged update upgraded with no rollback point while the caller
# printed the command as if one existed. Pins: snapshot first, prune is
# best-effort afterwards, and a failed snapshot exits non-zero so
# `koompi update` can refuse to continue.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SNAPSHOT="$ROOT/dots/.local/bin/koompi-snapshot"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin"

cat > "$T/bin/snapper" <<STUB
#!/usr/bin/env bash
if [[ "\${1:-}" == "list-configs" ]]; then echo "Config | Subvolume"; echo "root | /"; exit 0; fi
if [[ "\$1" == "-c" && "\$3" == "create" ]]; then
    printf '%s\\n' "\$*" >> "$T/order"
    [[ -e "$T/create-fails" ]] && exit 1
    echo 42
    exit 0
fi
if [[ "\$1" == "-c" ]]; then printf '%s\\n' "\$*" >> "$T/order"; exit 0; fi
exit 0
STUB

# sudo passes commands through, so the prune attempts reach the paccache shim
# and get recorded; the shim fails like an unprivileged run against root's cache.
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "paccache \$*" >> "%s"\nexit 1\n' "$T/order" > "$T/bin/paccache"
printf '#!/usr/bin/env bash\nexec "$@"\n' > "$T/bin/sudo"
chmod +x "$T/bin/snapper" "$T/bin/paccache" "$T/bin/sudo"

PATH="$T/bin:$PATH"
export PATH

out="$(bash "$SNAPSHOT" --pre-update 2>&1 < /dev/null)"
rc=$?
[[ $rc -eq 0 ]] || fail "a failed cache prune must not fail the pre-update run (rc=$rc): $out"

grep -q 'paccache' "$T/order" || fail "the prune was not attempted at all"
# The rollback point must exist before anything prunes: create before paccache.
[[ "$(grep -n 'create' "$T/order" | head -1 | cut -d: -f1)" ]] || fail "snapper never created a snapshot"
first_create="$(grep -n 'create' "$T/order" | head -1 | cut -d: -f1)"
first_paccache="$(grep -n 'paccache' "$T/order" | head -1 | cut -d: -f1)"
(( first_create < first_paccache )) \
    || fail "the cache prune ran before the snapshot again (line $first_paccache vs $first_create)"
grep -q -- '--type pre' "$T/order" || fail "the snapshot is not marked as a pre-update snapshot"
grep -qi 'prune failed\|skipping cache prune' <<<"$out" \
    || fail "a tolerated prune failure was reported as success or said nothing: $out"

# A snapshot that cannot be created must be a loud non-zero exit, because the
# caller refuses to upgrade without one.
touch "$T/create-fails"
out="$(bash "$SNAPSHOT" --pre-update 2>&1 < /dev/null)"
rc=$?
[[ $rc -ne 0 ]] || fail "a failed snapshot creation exited 0: $out"
grep -q 'could not create the pre-update snapshot' <<<"$out" \
    || fail "the failure was silent: $out"

exit 0