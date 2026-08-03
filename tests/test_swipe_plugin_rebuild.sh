#!/usr/bin/env bash
# Hyprland refuses a plugin built against a different Hyprland, so an OS upgrade
# silently disarms the swipe-progress plugin unless a pacman hook rebuilds it.
#
# Two things matter: it produces a plugin when it can, and it never fails the pacman
# transaction when it cannot. g++, pkg-config and make are stubbed.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
REBUILD="$REPO_ROOT/plugins/koompi-swipe-progress/rebuild"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

fail() { printf '%s\n' "$1" >&2; exit 1; }

[[ -x "$REBUILD" ]] || fail 'plugins/koompi-swipe-progress/rebuild is missing or not executable'

mkdir -p "$tmp/src" "$tmp/bin"
touch "$tmp/src/main.cpp" "$tmp/src/Makefile"

cat > "$tmp/bin/pkg-config" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "--exists" ]] && exit 0
[[ "$1" == "--modversion" ]] && { echo 9.9.9; exit 0; }
exit 0
EOF
cat > "$tmp/bin/g++" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
# Stands in for the real build: writes the .so the script then installs.
cat > "$tmp/bin/make" <<'EOF'
#!/usr/bin/env bash
dir=""
while [[ $# -gt 0 ]]; do
    [[ "$1" == "-C" ]] && { dir="$2"; shift 2; continue; }
    shift
done
printf 'stub-plugin\n' > "$dir/koompi-swipe-progress.so"
exit 0
EOF
chmod +x "$tmp/bin"/*

out="$tmp/out/koompi-swipe-progress.so"
env PATH="$tmp/bin:$PATH" KOOMPI_SWIPE_SRC="$tmp/src" KOOMPI_SWIPE_OUT="$out" \
    "$REBUILD" >/dev/null 2>&1 ||
    fail 'rebuild exited non-zero on the happy path, which would fail the pacman transaction'
[[ -f "$out" ]] || fail 'rebuild did not install a plugin'
[[ -x "$out" ]] || fail 'the installed plugin is not executable'

# A build that breaks after a Hyprland API change must not take the upgrade with
# it: the old plugin stays, Hyprland declines it, the desktop carries on.
cat > "$tmp/bin/make" <<'EOF'
#!/usr/bin/env bash
exit 2
EOF
chmod +x "$tmp/bin/make"
printf 'previous\n' > "$out"

env PATH="$tmp/bin:$PATH" KOOMPI_SWIPE_SRC="$tmp/src" KOOMPI_SWIPE_OUT="$out" \
    "$REBUILD" >/dev/null 2>&1 ||
    fail 'rebuild exited non-zero after a failed build, which would fail the pacman transaction'
[[ "$(cat "$out")" == previous ]] || fail 'a failed rebuild clobbered the working plugin'

# No compiler on the machine at all.
rm -f "$tmp/bin/g++"
env PATH="$tmp/bin:$PATH" KOOMPI_SWIPE_SRC="$tmp/src" KOOMPI_SWIPE_OUT="$out" \
    "$REBUILD" >/dev/null 2>&1 ||
    fail 'rebuild exited non-zero with no compiler, which would fail the pacman transaction'
[[ "$(cat "$out")" == previous ]] || fail 'rebuild removed the plugin when it could not build one'

# The hook has to actually be wired to a Hyprland upgrade, or none of the above runs.
hook="$REPO_ROOT/sdata/dist-arch/koompi-swipe-progress/koompi-swipe-progress.hook"
[[ -f "$hook" ]] || fail 'the pacman hook is missing'
grep -q '^Target = hyprland$' "$hook" || fail 'the hook does not trigger on hyprland'
grep -q '^Operation = Upgrade$' "$hook" || fail 'the hook does not trigger on upgrade'
grep -q '/usr/lib/koompi/hyprland/rebuild' "$hook" || fail 'the hook does not run the rebuild script'

# A pinned dependency would refuse the Hyprland upgrade instead of surviving it.
grep -q 'depends=(hyprland)' "$REPO_ROOT/sdata/dist-arch/koompi-swipe-progress/PKGBUILD" ||
    fail 'koompi-swipe-progress no longer depends on an unpinned hyprland'

exit 0
