# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. The global menu daemon, zig and rust: the shell prefers rust when present.

# The global menu daemon is Zig source in the shell tree; zig-out/ is
# gitignored, so a fresh clone has no binary and the menu silently stays empty.
setup_global_menu() {
    step "Global menu daemon"
    # The shell resolves the binary at ../scripts/global-menu/zig-out/bin from
    # its own QML, so it has to be built where the config was installed, not in
    # the checkout. ./setup calls this after the files step for that reason.
    local src="${XDG_CONFIG_HOME}/quickshell/koompi/scripts/global-menu"
    [[ -d "$src" ]] || {
        warn "the shell config is not installed, so there is nowhere to build the daemon"
        warn "run './setup install --only-files' first, then './setup install --only-setups'"
        return 0
    }
    if ! zig_usable; then
        warn "zig ${ZIG_MIN} or newer not found; the global menu will be empty until it is built."
        warn "Install one, then re-run: ./setup install --only-setups"
        return 0
    fi
    # prefix stays zig-out/ in $src (the QML resolves it there); only the cache moves out
    run_in_dir "$src" zig build \
        --cache-dir "$XDG_CACHE_HOME/koompi/build/global-menu/cache" \
        --global-cache-dir "$XDG_CACHE_HOME/zig" \
        -Doptimize=ReleaseSafe
    ok "global-menu-daemon built"
}

# The Rust daemon answers the same stdio protocol as the zig one above, and the
# shell prefers it when it is present. Both are kept while the port is proven:
# tests/test_globalmenu.sh runs the one conformance suite against each. Unlike
# the zig build this installs to a normal bin dir, because nothing resolves it
# by a path relative to the QML.
setup_globalmenu_rs() {
    step "Global menu daemon (rust)"
    local src="$REPO_ROOT/globalmenu"
    local build_root="$XDG_CACHE_HOME/koompi/build/globalmenu"
    local binary="$build_root/release/global-menu-daemon"
    [[ -f "$src/Cargo.toml" ]] || { warn "globalmenu source not found, skipping"; return 0; }
    if ! cargo_usable; then
        warn "cargo ${RUST_MIN} or newer not found; the shell falls back to the zig daemon."
        warn "Install one, then re-run: ./setup install --only-setups"
        return 0
    fi
    # Same discipline as the zig builds: nothing generated lands in the checkout.
    ( cd "$src" && run cargo build --release --locked --target-dir "$build_root" )
    run install -Dm755 "$binary" "$XDG_BIN_HOME/koompi-global-menu-daemon"
    manifest_add "$XDG_BIN_HOME/koompi-global-menu-daemon"
    ok "koompi-global-menu-daemon installed"
}
