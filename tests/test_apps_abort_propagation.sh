#!/usr/bin/env bash
# Guards: a failed application recipe must not end in "applications installed".
# arch_install_pkgbuild returns 1 without dying when the build yields no package
# (or makepkg was skipped at the prompt); install-apps.sh ignored that status
# and apps.sh ignored the recipe's, so the run went on into the agent installs
# and printed ok three lines under the error.
#
# Everything the step would touch is shadowed; asserts on control flow only.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

[[ -f "$REPO_ROOT/sdata/dist-arch/install-apps.sh" ]] || {
    printf 'no arch app recipe to test against; skipping\n'
    exit 0
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
stub="$tmp/bin"
mkdir -p "$stub" "$tmp/home"

cat > "$stub/makepkg" <<'STUB'
#!/usr/bin/env bash
# Predicts a package, then "builds" without producing it: the no-die failure.
[[ "$1" == "--packagelist" ]] && { printf '/nonexistent/koompi-apps-1.0-1-any.pkg.tar.zst\n'; exit 0; }
exit 0
STUB

cat > "$stub/pacman" <<'STUB'
#!/usr/bin/env bash
case "$1" in
    -Q)  exit 1 ;;   # koompi-apps not installed
    -T)  exit 0 ;;   # no missing depends[], so paru is never asked to resolve
    -Qq) exit 0 ;;   # mpvpaper "present": no AUR prompt on the way past
    *)   exit 0 ;;
esac
STUB

# The recipe must reach the code it guards, so paru, git and sudo all "work".
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/paru"
printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/git"
cat > "$stub/sudo" <<'STUB'
#!/usr/bin/env bash
[[ "$1" == -* ]] && exit 0
exec "$@"
STUB
# Every agent CLI "installed", so the old flow reached its ok line without
# needing npm or curl, and nothing here tries the network.
for agent in claude codex pi herdr nvim; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$stub/$agent"
done
for guard in hyprctl killall qs quickshell setsid curl npm; do
    printf '#!/usr/bin/env bash\nexit 1\n' > "$stub/$guard"
done
chmod +x "$stub"/*

printf 'ID=arch\n' > "$tmp/os-release"

out="$tmp/out"
env -u HYPRLAND_INSTANCE_SIGNATURE \
    PATH="$stub:$PATH" HOME="$tmp/home" NO_COLOR=1 KOOMPI_OS_RELEASE="$tmp/os-release" \
    "$REPO_ROOT/setup" install --only-apps --yes \
    > "$out" 2>&1 < /dev/null

fail() { printf '%s\n--- output ---\n%s\n' "$1" "$(cat "$out")" >&2; exit 1; }

grep -q 'built no package to install' "$out" ||
    fail 'the build failure never surfaced; the test did not reach the code it guards'

grep -q 'application recipe failed' "$out" ||
    fail 'the failed recipe was not reported by install_apps'

grep -q 'applications installed' "$out" &&
    fail 'reported "applications installed" after the application recipe failed'

grep -q '==> KOOMPI Workbench' "$out" &&
    fail 'went on to the agent installs after the application recipe failed'

printf 'apps abort propagation test passed\n'
