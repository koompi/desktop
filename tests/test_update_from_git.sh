#!/usr/bin/env bash
# The from-git route is the only one that reaches a user today: [koompi] is not
# published, so `koompi update` either takes this route outright or falls back
# to it. What it promises is that the checkout's content becomes the user's
# desktop - the tools in ~/.local/bin, the shell tree in
# ~/.config/quickshell/koompi, and the koompi-sysdefaults drop-ins under
# /usr/local/lib, applied rather than merely copied.
#
# Driven, not read: the real install_files and setup_low_ram_defaults run
# against a throwaway HOME with sudo sandboxed into a fake root. Nothing is
# cloned - the checkout is a directory of symlinks to this tree, deliberately
# without .gitmodules so install_files' submodule branch cannot reach the
# network - and nothing on this machine is written.
#
# shellcheck disable=SC2016,SC2088  # the bash -c bodies expand in the child; messages name user paths
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# XDG_* are read at source time by common.sh and by the update engine, so a
# value inherited from the shell running the tests would redirect the install
# out of the throwaway HOME and into the real one.
clean_env=(env -u XDG_BIN_HOME -u XDG_CACHE_HOME -u XDG_CONFIG_HOME
           -u XDG_DATA_HOME -u XDG_STATE_HOME -u BACKUP_ROOT NO_COLOR=1)

# install_files' own exclude list, as a find(1) filter: a stray .pyc left in
# dots/ by another test is not a file the route is supposed to deliver.
artefacts=(! -path '*/.git/*' ! -name '.git' ! -name '.gitignore' ! -name '.qmlls.ini'
           ! -path '*/zig-out/*' ! -path '*/.zig-cache/*'
           ! -path '*/__pycache__/*' ! -name '*.pyc')

# A checkout that owns dots/ and sdata/ without being a git repository.
repo="$tmp/repo"
mkdir -p "$repo"
ln -s "$ROOT/dots" "$repo/dots"
ln -s "$ROOT/sdata" "$repo/sdata"
ln -s "$ROOT/docs" "$repo/docs"

# --- 1. koompi update hands the machine to that checkout's ./setup update ----
# update_from_git is the whole of the route's dispatch: resolve the checkout,
# refuse under a locked session, then run ./setup update. A change that drops
# the handoff, the route label or --yes shows up here.
route_home="$tmp/route-home"
mkdir -p "$route_home/.local/state/koompi"
fake_checkout="$tmp/fake-checkout"
mkdir -p "$fake_checkout"
cat > "$fake_checkout/setup" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$@" > "$KOOMPI_TEST_ARGV"
EOF
chmod +x "$fake_checkout/setup"
printf '%s\n' "$fake_checkout" > "$route_home/.local/state/koompi/repo-path"

route="$(
    "${clean_env[@]}" HOME="$route_home" KOOMPI_TEST_ARGV="$tmp/route-argv" \
    bash -c '
        set -uo pipefail
        KOOMPI_UPDATE_LIBRARY=1
        source "$1" || exit 1
        # This machine may itself have a locked session or a full disk;
        # neither is what the assertion below is about.
        session_locked() { return 1; }
        require_free_space() { return 0; }
        DRY_RUN=false
        ASSUME_YES=true
        update_from_git >/dev/null 2>&1 || exit 1
        printf "%s\n" "$UPDATE_ROUTE"
    ' _ "$ROOT/dots/.local/share/koompi/libexec/update"
)" || fail "update_from_git failed"

[[ "$route" == from-git ]] \
    || fail "koompi update did not record the from-git route: ${route:-none}"
[[ -f "$tmp/route-argv" ]] \
    || fail "koompi update never ran the checkout's ./setup"
diff -u - "$tmp/route-argv" >&2 <<'EOF' \
    || fail "koompi update called ./setup with the wrong arguments"
update
--yes
EOF

# run_update is what that ./setup then runs. The two steps that carry this
# tree to the user have to stay in it.
update_fn="$(sed -n '/^run_update() {/,/^}/p' "$ROOT/sdata/install/update.sh")"
[[ -n "$update_fn" ]] || fail "sdata/install/update.sh has no run_update"
grep -Fq 'run_setups' <<< "$update_fn" \
    || fail "run_update no longer runs the setups, so the sysdefaults never land on an update"
grep -Fq 'install_files' <<< "$update_fn" \
    || fail "run_update no longer installs files, so the tools and the shell tree never land on an update"

# --- 2. install_files delivers the tools and the shell tree -----------------
home="$tmp/home"
mkdir -p "$home"
install_files_run() {
    "${clean_env[@]}" HOME="$home" bash -c '
        set -uo pipefail
        REPO_ROOT="$1"; readonly REPO_ROOT
        DRY_RUN=false
        ASSUME_YES=true
        SKIP_BACKUP=false
        source "$REPO_ROOT/sdata/lib/common.sh" || exit 1
        source "$REPO_ROOT/sdata/install/files.sh" || exit 1
        install_files
    ' _ "$repo"
}
install_files_run > "$tmp/files.log" 2>&1 \
    || { cat "$tmp/files.log" >&2; fail "install_files failed"; }

# Every tool, byte for byte. The route rsyncs the whole directory rather than a
# manifest, so a tool added to dots/.local/bin needs no second edit anywhere -
# and this fails the moment that stops being true.
while IFS= read -r -d '' tool; do
    rel="${tool#"$ROOT/dots/.local/bin/"}"
    [[ -e "$home/.local/bin/$rel" ]] \
        || fail "~/.local/bin/$rel was not delivered"
    cmp -s -- "$tool" "$home/.local/bin/$rel" \
        || fail "~/.local/bin/$rel differs from the checkout's copy"
done < <(find "$ROOT/dots/.local/bin" -type f "${artefacts[@]}" -print0)
[[ -x "$home/.local/bin/koompi-factory-reset" ]] \
    || fail "koompi-factory-reset is not executable in ~/.local/bin"

# The shell tree, with the build artefacts install_files excludes left out.
shell_src="$ROOT/dots/.config/quickshell/koompi"
shell_dst="$home/.config/quickshell/koompi"
while IFS= read -r -d '' qml; do
    rel="${qml#"$shell_src/"}"
    cmp -s -- "$qml" "$shell_dst/$rel" \
        || fail "~/.config/quickshell/koompi/$rel is missing or stale"
done < <(find "$shell_src" -type f "${artefacts[@]}" -print0)

# The three destination classes, on a second run: the shell tree is mirrored
# (a file the user added is removed), ~/.local/bin is merged (a file the user
# added stays), and an override slot is never rewritten.
stale="$shell_dst/modules/koompi-stale-module.qml"
kept_bin="$home/.local/bin/my-own-tool"
keep_slot="$home/.config/hypr/custom/keybinds.lua"
printf 'stale\n' > "$stale"
printf 'mine\n' > "$kept_bin"
printf '// mine\n' > "$keep_slot"
install_files_run > "$tmp/files2.log" 2>&1 \
    || { cat "$tmp/files2.log" >&2; fail "the second install_files failed"; }
[[ ! -e "$stale" ]] \
    || fail "the shell tree is not mirrored; a file removed upstream would survive in ~/.config/quickshell/koompi"
[[ -e "$kept_bin" ]] \
    || fail "~/.local/bin is being mirrored, which deletes tools the user put there"
[[ "$(< "$keep_slot")" == '// mine' ]] \
    || fail "the update overwrote ~/.config/hypr/custom/keybinds.lua"

# --- 3. setup_low_ram_defaults installs the drop-ins and applies them -------
# sudo is sandboxed: install(1) is redirected under a fake root and every other
# call is only recorded, so this writes nothing outside $tmp.
fake_root="$tmp/fakeroot"
stub="$tmp/bin"
mkdir -p "$fake_root" "$stub"
cat > "$stub/sudo" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SUDO_LOG"
if [[ "$1" == install ]]; then
    exec "${@:1:$#-1}" "$FAKE_ROOT${!#}"
fi
exit 0
EOF
chmod +x "$stub/sudo"

"${clean_env[@]}" HOME="$tmp/setups-home" PATH="$stub:$PATH" \
    SUDO_LOG="$tmp/sudo.log" FAKE_ROOT="$fake_root" \
    bash -c '
        set -uo pipefail
        REPO_ROOT="$1"; readonly REPO_ROOT
        DRY_RUN=false
        ASSUME_YES=true
        OS_GROUP_ID=arch
        source "$REPO_ROOT/sdata/lib/common.sh" || exit 1
        source "$REPO_ROOT/sdata/install/setups.sh" || exit 1
        # The container, chroot and CI cases are _guards.sh business, not this
        # test s: pin both answers so the body always runs.
        systemd_running() { return 0; }
        systemd_user_running() { return 1; }
        setup_low_ram_defaults
    ' _ "$repo" > "$tmp/setups.log" 2>&1 \
    || { cat "$tmp/setups.log" >&2; fail "setup_low_ram_defaults failed"; }

src="$ROOT/sdata/dist-arch/koompi-sysdefaults/files/usr/lib"
while IFS= read -r -d '' file; do
    rel="${file#"$src/"}"
    landed="$fake_root/usr/local/lib/$rel"
    [[ -f "$landed" ]] || fail "/usr/local/lib/$rel was not installed"
    cmp -s -- "$file" "$landed" \
        || fail "/usr/local/lib/$rel differs from the package's copy, so the two routes have drifted"
done < <(find "$src" -type f -print0)

sudo_log="$(< "$tmp/sudo.log")"
grep -Fq 'systemctl restart systemd-sysctl.service' <<< "$sudo_log" \
    || fail "the sysctl drop-in was copied but never applied; a from-git user waits for a reboot"
grep -Fq 'systemctl restart systemd-oomd.service' <<< "$sudo_log" \
    || fail "the oomd drop-ins were copied but the daemon was never restarted"

echo "ok test_update_from_git.sh"
