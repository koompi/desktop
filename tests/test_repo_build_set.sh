#!/usr/bin/env bash
# The pacman-repo build loops (sdata/dist-arch/repo/build-repo.sh and the
# build-packages workflow) iterated koompi-*/, which misses ttf-koompi-star/:
# a package koompi-fonts-themes depends on and install-deps.sh builds, so the
# signed [koompi] repo could never satisfy its own metas (BUG-AUDIT H4). Pins
# both loops to every sdata/dist-arch/*/PKGBUILD: the script is run with
# makepkg, gpg and repo-add shadowed and the directories it visited compared;
# the workflow's glob is read out of the YAML and expanded the same way.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_ARCH="$REPO_ROOT/sdata/dist-arch"
SCRIPT="$DIST_ARCH/repo/build-repo.sh"
WORKFLOW="$REPO_ROOT/.github/workflows/build-packages.yml"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

expected="$tmp/expected"
for pkgbuild in "$DIST_ARCH"/*/PKGBUILD; do
    basename -- "$(dirname -- "$pkgbuild")"
done | sort > "$expected"
grep -qx 'ttf-koompi-star' "$expected" || fail "sdata/dist-arch/ttf-koompi-star/PKGBUILD is gone; the test's premise changed"

# 1. build-repo.sh, with everything that would build, sign or publish shadowed.
mkdir -p "$tmp/bin"
cat > "$tmp/bin/makepkg" <<SH
#!/usr/bin/env bash
basename -- "\$PWD" >> "$tmp/built"
SH
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/gpg"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/repo-add"
chmod +x "$tmp/bin"/*
: > "$tmp/built"
if ! PATH="$tmp/bin:$PATH" OUTDIR="$tmp/out" bash "$SCRIPT" > "$tmp/script.log" 2>&1; then
    cat "$tmp/script.log" >&2
    fail "build-repo.sh exited non-zero with makepkg/gpg/repo-add shadowed"
fi
sort "$tmp/built" > "$tmp/built.sorted"
if ! diff -u "$expected" "$tmp/built.sorted" > "$tmp/script.diff"; then
    cat "$tmp/script.diff" >&2
    fail "build-repo.sh does not build every sdata/dist-arch/*/PKGBUILD (- missing, + extra)"
fi

# 2. The workflow: the loop's glob, expanded against this checkout.
glob="$(sed -n 's/^[[:space:]]*for pkgdir in \(.*\); do[[:space:]]*$/\1/p' "$WORKFLOW" | head -1)"
[[ -n "$glob" ]] || fail "build-packages.yml has no 'for pkgdir in ...; do' loop to check"
GITHUB_WORKSPACE="$REPO_ROOT" bash -c "for pkgdir in $glob; do [ -f \"\$pkgdir/PKGBUILD\" ] && basename -- \"\$pkgdir\"; done" \
    | sort > "$tmp/workflow.sorted"
if ! diff -u "$expected" "$tmp/workflow.sorted" > "$tmp/workflow.diff"; then
    cat "$tmp/workflow.diff" >&2
    fail "build-packages.yml does not build every sdata/dist-arch/*/PKGBUILD (- missing, + extra)"
fi

(( failed == 0 )) || exit 1
printf 'ok: both repo build loops cover all %d PKGBUILDs\n' "$(wc -l < "$expected")"
