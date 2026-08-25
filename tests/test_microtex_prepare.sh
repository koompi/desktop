#!/usr/bin/env bash
# koompi-microtex-git's prepare() used to rewrite gtksourceviewmm-3.0 to a
# hard-coded gtksourceviewmm-4.0 (and tinyxml2.so.10 to .so.11, which matched
# nothing in upstream's CMakeLists), so the next soname bump would have broken
# the build again (BUG-AUDIT L21). Runs the PKGBUILD's prepare() against a
# CMakeLists stub with patch and pkg-config shadowed, and checks the module
# name comes from what pkg-config reports rather than from the recipe.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKGBUILD="$REPO_ROOT/sdata/dist-arch/koompi-microtex-git/PKGBUILD"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

mkdir -p "$tmp/bin"
printf '#!/usr/bin/env bash\nexit 0\n' > "$tmp/bin/patch"
cat > "$tmp/bin/pkg-config" <<'SH'
#!/usr/bin/env bash
[[ "$1" == "--list-all" ]] || { echo "unexpected pkg-config $*" >&2; exit 2; }
cat "$FAKE_PC_LIST"
SH
chmod +x "$tmp/bin"/*

# prepare() as makepkg runs it: sourced, then called from $srcdir.
run_prepare() {
    local srcdir="$1"
    (
        set -e
        cd "$srcdir"
        # shellcheck disable=SC1090  # the PKGBUILD path is computed, not a literal
        source "$PKGBUILD"
        prepare
    )
}

# What upstream's CMakeLists says (NanoMichael/MicroTeX 0e3707f, lines 55 and 215).
stub() {
    mkdir -p "$1/MicroTeX"
    cat > "$1/MicroTeX/CMakeLists.txt" <<'CM'
    pkg_check_modules(tinyxml2 REQUIRED IMPORTED_TARGET tinyxml2)
    pkg_check_modules(GSVMM REQUIRED IMPORTED_TARGET gtksourceviewmm-3.0)
CM
}

# 1. The module installed today.
stub "$tmp/one"
printf 'gtksourceviewmm-4.0  gtksourceviewmm - C++ binding\ngtkmm-3.0  gtkmm - C++ binding\n' > "$tmp/pc.one"
PATH="$tmp/bin:$PATH" FAKE_PC_LIST="$tmp/pc.one" run_prepare "$tmp/one" > "$tmp/one.log" 2>&1 \
    || { cat "$tmp/one.log" >&2; fail "prepare() failed with gtksourceviewmm-4.0 installed"; }
grep -q 'IMPORTED_TARGET gtksourceviewmm-4.0)' "$tmp/one/MicroTeX/CMakeLists.txt" \
    || fail "CMakeLists was not pointed at the installed gtksourceviewmm-4.0"

# 2. The bump after it: no recipe edit needed.
stub "$tmp/two"
printf 'gtksourceviewmm-5.0  gtksourceviewmm - C++ binding\n' > "$tmp/pc.two"
PATH="$tmp/bin:$PATH" FAKE_PC_LIST="$tmp/pc.two" run_prepare "$tmp/two" > "$tmp/two.log" 2>&1 \
    || { cat "$tmp/two.log" >&2; fail "prepare() failed with gtksourceviewmm-5.0 installed"; }
grep -q 'IMPORTED_TARGET gtksourceviewmm-5.0)' "$tmp/two/MicroTeX/CMakeLists.txt" \
    || fail "CMakeLists was not pointed at the installed gtksourceviewmm-5.0 (still pinned?)"
grep -q 'IMPORTED_TARGET tinyxml2)' "$tmp/two/MicroTeX/CMakeLists.txt" \
    || fail "the tinyxml2 line was rewritten; it is found through pkg-config and must stay"

# 3. Nothing installed: prepare() says so and fails, instead of leaving 3.0 for cmake to trip on.
stub "$tmp/none"
: > "$tmp/pc.none"
if PATH="$tmp/bin:$PATH" FAKE_PC_LIST="$tmp/pc.none" run_prepare "$tmp/none" > "$tmp/none.log" 2>&1; then
    fail "prepare() succeeded with no gtksourceviewmm module installed"
fi
grep -q 'gtksourceviewmm' "$tmp/none.log" || fail "prepare() failed without naming the missing module"

(( failed == 0 )) || exit 1
echo "ok: microtex prepare() takes the gtksourceviewmm module from pkg-config"
