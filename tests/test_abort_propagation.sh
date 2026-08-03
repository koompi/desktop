#!/usr/bin/env bash
# Guards: a step that aborts must stop the run. `( cd "$dir" && run makepkg )` hid
# it - run aborts via die, die is exit, and inside `( )` that ends only the subshell,
# after which install_deps, the recipe loop and `$DO_DEPS && install_deps` all
# ignored the status and kept installing against packages never built.
#
# Everything the run would touch is shadowed; asserts on control flow only.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -f "$REPO_ROOT/sdata/dist-arch/install-deps.sh" ]] || {
    printf 'no arch recipe to test against; skipping\n'
    exit 0
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/home"

cat > "$stub/makepkg" <<'EOF'
#!/usr/bin/env bash
# Answers the pre-build query, then fails the build itself.
[[ "$1" == "--packagelist" ]] && { printf '/nonexistent/koompi-test-1-1-x86_64.pkg.tar.zst\n'; exit 0; }
printf 'makepkg: simulated build failure\n' >&2
exit 1
EOF

cat > "$stub/pacman" <<'EOF'
#!/usr/bin/env bash
case "$1" in
    -Qq) [[ $# -eq 1 ]] && exit 0; exit 1 ;;   # nothing stale, nothing installed
    -Q)  exit 1 ;;                             # so every meta counts as pending
    -T)  exit 0 ;;                             # no missing depends[], so no yay
    *)   exit 0 ;;
esac
EOF

cat > "$stub/git" <<'EOF'
#!/usr/bin/env bash
# An empty branch name makes update_pull report a detached HEAD and return
# without fetching. No network, no touching the real checkout.
exit 0
EOF

# yay is never reached (pacman -T reports nothing missing) but must exist, or
# arch_install_yay tries to build it.
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/yay"
# sudo has to run its argument so the stubbed pacman above is what answers.
printf '#!/usr/bin/env bash\n[[ "$1" == -* ]] && exit 0\nexec "$@"\n' > "$stub/sudo"
# Belt and braces: nothing may reload or kill the caller's live session.
for guard in hyprctl killall qs quickshell setsid; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/$guard"
done
chmod +x "$stub"/*

out="$tmp/out"
# HYPRLAND_INSTANCE_SIGNATURE is cleared as well as stubbed: reload_session must
# not even consider touching the session that is running this test.
env -u HYPRLAND_INSTANCE_SIGNATURE \
    PATH="$stub:$PATH" HOME="$tmp/home" NO_COLOR=1 \
    "$REPO_ROOT/setup" update --yes --no-setups --no-files \
    > "$out" 2>&1 < /dev/null
status=$?

fail() { printf '%s\n--- output ---\n%s\n' "$1" "$(cat "$out")" >&2; exit 1; }

(( status != 0 )) || fail 'setup update exited 0 after a build was aborted'

grep -q 'command failed: makepkg' "$out" ||
    fail 'the build failure never surfaced; the test did not reach the code it guards'

grep -q 'dependencies installed' "$out" &&
    fail 'reported "dependencies installed" after the dependency step aborted'

# The steps that follow must not have run against a half-built system.
grep -q 'KOOMPI is up to date' "$out" &&
    fail 'the update reported success after aborting'

printf 'abort propagation test passed\n'
