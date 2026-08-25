# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. The native `koompi` command, built from this checkout.

# The native `koompi` command is the front door to desktop maintenance and the
# shipped helpers. Build it from the same checkout being installed so its
# command surface always matches the scripts and desktop version beside it.
setup_koompi_cli() {
    step "KOOMPI command line"
    local src="$REPO_ROOT/cli"
    local build_root="$XDG_CACHE_HOME/koompi/build/cli"
    local binary="$build_root/out/bin/koompi"
    [[ -f "$src/build.zig" ]] || { warn "CLI source not found, skipping"; return 0; }
    if ! zig_usable; then
        warn "zig ${ZIG_MIN} or newer not found; the koompi command cannot be built."
        warn "Install one, then re-run: ./setup install --only-setups"
        return 0
    fi
    run mkdir -p "$build_root"
    # Keep generated objects and the install prefix out of the checkout. A
    # user's KOOMPI source tree should stay clean after every install/update.
    run_in_dir "$src" zig build \
        --cache-dir "$build_root/cache" \
        --global-cache-dir "$XDG_CACHE_HOME/zig" \
        --prefix "$build_root/out" \
        -Doptimize=ReleaseSafe
    run install -Dm755 "$binary" "$XDG_BIN_HOME/koompi"
    manifest_add "$XDG_BIN_HOME/koompi"
    ok "koompi CLI installed"
}
