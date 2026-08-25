#!/usr/bin/env bash
# `koompi update` on a packaged install used to print "packages up to date"
# even though nothing serves koompi-shell from anywhere (the [koompi] repo is
# a skeleton), so a packaged user never received a committed change. These
# tests pin the honest behaviour: no repo + no moved package => say so and run
# the git route; either evidence of delivery => stay packaged; a failed
# pre-update snapshot refuses the upgrade unless --yes accepts the risk.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$ROOT/dots/.local/share/koompi/libexec/update"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v jq >/dev/null || { echo "jq not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/.local/state/koompi"

# --- command shims ----------------------------------------------------------
# pacman: koompi-shell is installed; -Syu "upgrades" by appending a new
# version line, unless the test pins the cache as static.
cat > "$T/bin/pacman" <<STUB
#!/usr/bin/env bash
if [[ "\$1" == "-Qq" && "\${2:-}" == "koompi-shell" ]]; then exit 0; fi
if [[ "\$1" == "-Qq" ]]; then cat "$T/versions"; exit 0; fi
if [[ "\$1" == "-Syu" ]]; then
    touch "$T/syu-ran"
    echo "koompi-shell 9.9-1" >> "$T/versions"
    sort -o "$T/versions" "$T/versions"
    exit 0
fi
exit 0
STUB
printf 'koompi-shell 1.1-1\nkoompi-hyprland-config 1.0-2\n' > "$T/versions"

# pacman-conf: repo list driven by a file the test controls.
cat > "$T/bin/pacman-conf" <<STUB
#!/usr/bin/env bash
if [[ "\${1:-}" == "--repo-list" ]]; then cat "$T/repos"; exit 0; fi
exit 0
STUB
printf 'core\nextra\nmultilib\n' > "$T/repos"

# sudo passes the recorded command through to whatever shim owns it.
printf '#!/usr/bin/env bash\nexec "$@"\n' > "$T/bin/sudo"
# AUR helpers and the hook must never reach the real ones from here.
printf '#!/usr/bin/env bash\ntouch "$T/aur-ran"\nexit 0\n' > "$T/bin/paru"
printf '#!/usr/bin/env bash\ntouch "$T/aur-ran"\nexit 0\n' > "$T/bin/yay"
printf '#!/usr/bin/env bash\necho "hook \$KOOMPI_HOOK_UPDATE_METHOD" >> "$T/hook"\nexit 0\n' > "$T/bin/koompi-hook"

# A checkout the fallback can be handed to: ./setup records how it was called.
mkdir -p "$T/repo"
cat > "$T/repo/setup" <<STUB
#!/usr/bin/env bash
printf '%s\\n' "\$*" >> "$T/setup-called"
exit 0
STUB
chmod +x "$T/bin/pacman" "$T/bin/pacman-conf" "$T/bin/sudo" \
         "$T/bin/paru" "$T/bin/yay" "$T/bin/koompi-hook" "$T/repo/setup"
echo "$T/repo" > "$T/home/.local/state/koompi/repo-path"

export PATH="$T/bin:$PATH"
export HOME="$T/home"
export XDG_STATE_HOME="$T/home/.local/state"
unset HYPRLAND_INSTANCE_SIGNATURE   # keep reload_session away from the live session
export NO_COLOR=1

run_update() { bash "$UPDATE" "$@" 2>&1 < /dev/null; }

# --- 1. no [koompi] repo, static versions: the fallback must fire ------------
out="$(run_update --dry-run)"
grep -q 'delivered nothing of ours' <<<"$out" \
    || fail "the honesty line is missing: $out"
[[ "$(tail -1 "$T/setup-called" 2>/dev/null)" == "update --dry-run" ]] \
    || fail "the git fallback did not run ./setup update --dry-run"
grep -qi 'falling back to the git route' <<<"$out" \
    || fail "the output does not name the route that ran"
grep -q 'packages up to date' <<<"$out" \
    && fail "'packages up to date' must not stand when nothing was delivered"

# --- 2. repo enabled: packaged route owns it ---------------------------------
rm -f "$T/setup-called" "$T/syu-ran"
printf 'core\nextra\nkoompi\n' > "$T/repos"
out="$(run_update --dry-run)"
grep -q 'packages up to date (route: packaged)' <<<"$out" \
    || fail "a configured [koompi] repo should end as a packaged update: $out"
[[ -e "$T/setup-called" ]] && fail "the git route ran although the repo is configured"

# --- 3. no repo, but the upgrade moved a koompi-* package --------------------
rm -f "$T/setup-called"
printf 'core\nextra\nmultilib\n' > "$T/repos"
out="$(run_update --yes)"
grep -q 'packages up to date (route: packaged)' <<<"$out" \
    || fail "moved koompi-* packages mean the packaged route delivered: $out"
[[ -e "$T/setup-called" ]] && fail "the git route ran although a package moved"

# --- 4. a failed pre-update snapshot refuses the upgrade ---------------------
rm -f "$T/syu-ran"
cat > "$T/bin/koompi-snapshot" <<'STUB'
#!/usr/bin/env bash
echo "koompi-snapshot: simulated failure" >&2
exit 1
STUB
chmod +x "$T/bin/koompi-snapshot"
out="$(run_update)"
rc=$?
[[ $rc -ne 0 ]] || fail "a missing snapshot must fail the update without --yes"
grep -q 'refusing to upgrade' <<<"$out" \
    || fail "a failed snapshot must stop the upgrade without --yes: $out"
[[ -e "$T/syu-ran" ]] && fail "the upgrade ran although no snapshot was created"
out="$(run_update --yes)"
rc=$?
[[ $rc -eq 0 ]] || fail "--yes should accept the risk and finish: $out"
grep -q 'continuing (--yes)' <<<"$out" \
    || fail "--yes must be allowed to accept the missing snapshot: $out"
[[ -e "$T/syu-ran" ]] || fail "--yes accepted the risk but no upgrade ran"

exit 0