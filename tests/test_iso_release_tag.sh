#!/usr/bin/env bash
# build-iso.yml tagged the GitHub Release "iso-<iso_version>", and
# profiledef.sh's iso_version is the date alone, so a second dispatch on the
# same day built the whole ISO and then died at `gh release create` on the
# existing tag (BUG-AUDIT L23). Runs the workflow's publish step, as written in
# the YAML, with gh shadowed: two builds from different commits on one day get
# different tags, and a re-run of the same commit uploads over its own release
# instead of trying to create it again.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW="$REPO_ROOT/.github/workflows/build-iso.yml"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# The publish step's script, read out of the YAML so the test runs the real text.
python3 - "$WORKFLOW" > "$tmp/publish.sh" <<'PY' || { echo "FAIL: could not read the publish step out of build-iso.yml" >&2; exit 1; }
import sys, yaml
wf = yaml.safe_load(open(sys.argv[1]))
steps = [s for s in wf["jobs"]["build-iso"]["steps"] if s.get("name") == "Publish GitHub Release"]
if len(steps) != 1:
    sys.exit("build-iso.yml no longer has exactly one 'Publish GitHub Release' step")
print(steps[0]["run"])
PY

# gh: `release view` succeeds for tags created earlier in this test; everything is logged.
mkdir -p "$tmp/bin" "$tmp/out"
cat > "$tmp/bin/gh" <<SH
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "$tmp/gh.log"
case "\$1 \$2" in
    "release view")   grep -qx -- "\$3" "$tmp/tags" 2>/dev/null ;;
    "release create") grep -qx -- "\$3" "$tmp/tags" 2>/dev/null && { echo "gh: release \$3 already exists" >&2; exit 1; }
                      printf '%s\n' "\$3" >> "$tmp/tags" ;;
    "release upload") grep -qx -- "\$3" "$tmp/tags" 2>/dev/null || { echo "gh: release \$3 not found" >&2; exit 1; } ;;
    *) echo "gh: unexpected: \$*" >&2; exit 2 ;;
esac
SH
chmod +x "$tmp/bin/gh"
: > "$tmp/out/koompi-2026.08.25-x86_64.iso"
: > "$tmp/out/SHA256SUMS"

publish() {
    ( cd "$tmp/out" && PATH="$tmp/bin:$PATH" GITHUB_REPOSITORY=koompi/desktop GITHUB_SHA="$1" bash "$tmp/publish.sh" )
}

publish 0123456789abcdef0123456789abcdef01234567 > "$tmp/run1.log" 2>&1 \
    || { cat "$tmp/run1.log" >&2; fail "first publish of the day failed"; }
publish 89abcdef0123456789abcdef0123456789abcdef > "$tmp/run2.log" 2>&1 \
    || { cat "$tmp/run2.log" >&2; fail "second publish the same day, from another commit, failed"; }
publish 89abcdef0123456789abcdef0123456789abcdef > "$tmp/run3.log" 2>&1 \
    || { cat "$tmp/run3.log" >&2; fail "re-running the same commit failed"; }

grep -q '^release create iso-koompi-2026.08.25-x86_64-0123456 ' "$tmp/gh.log" \
    || fail "the first tag does not carry the ISO version and the short commit"
grep -q '^release create iso-koompi-2026.08.25-x86_64-89abcde ' "$tmp/gh.log" \
    || fail "the second build the same day did not get a tag of its own"
grep -q '^release upload iso-koompi-2026.08.25-x86_64-89abcde .*--clobber' "$tmp/gh.log" \
    || fail "re-running the same commit did not upload over its own release"
(( $(grep -c '^release create' "$tmp/gh.log") == 2 )) \
    || fail "expected exactly two 'release create' calls, got: $(grep -c '^release create' "$tmp/gh.log")"
grep -q -- '--repo koompi/desktop' "$tmp/gh.log" || fail "the repo flag was lost"
grep -q -- 'koompi-2026.08.25-x86_64.iso SHA256SUMS' "$tmp/gh.log" || fail "the ISO and checksum are not both attached"

(( failed == 0 )) || exit 1
echo "ok: same-day ISO builds get distinct tags and a re-run replaces its own assets"
