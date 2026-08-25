# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. The assistant long-term memory daemon: find its source, build it, prove it answers.

# The assistant's long-term memory. services/MemoryService.qml execs
# ~/.local/bin/koompi-agent-memd and, until this existed, nothing on a fresh
# machine ever put a binary there: the assistant forgot the owner's name, their
# preferences and their projects at every logout and said nothing about why.
#
# Its own repository, so the source is a sibling checkout where there is one and
# a clone into the build cache otherwise. Same shape as setup_shell_services in
# system.sh: build, install to a bin dir, and name what is lost when the toolchain
# is not there.
readonly MEMD_REPO_URL="https://github.com/rithythul/koompi-agent-memd.git"

# Answers in MEMD_SRC rather than on stdout: run() and try() echo the command
# they are about to run, and a command substitution would capture that echo as
# part of the path.
MEMD_SRC=''
memd_source() {
    local sibling cached
    MEMD_SRC=''
    sibling="$(dirname -- "$REPO_ROOT")/koompi-agent-memd"
    if [[ -f "$sibling/Cargo.toml" ]]; then
        MEMD_SRC="$sibling"
        return 0
    fi

    cached="$XDG_CACHE_HOME/koompi/src/koompi-agent-memd"
    if [[ -f "$cached/Cargo.toml" ]]; then
        try git -C "$cached" pull --ff-only \
            || warn "could not update $cached; building the checkout that is already there"
        MEMD_SRC="$cached"
        return 0
    fi

    have git || { warn "git not found, and no koompi-agent-memd checkout beside this one"; return 1; }
    mkdir -p "$(dirname -- "$cached")"
    try git clone --depth 1 "$MEMD_REPO_URL" "$cached" || return 1
    MEMD_SRC="$cached"
    [[ "$DRY_RUN" == true ]] && return 0
    [[ -f "$cached/Cargo.toml" ]] || { warn "the clone left no Cargo.toml at $cached"; return 1; }
}

setup_agent_memory() {
    step "Assistant memory"
    local build_root binary
    build_root="$XDG_CACHE_HOME/koompi/build/koompi-agent-memd"
    binary="$build_root/release/koompi-agent-memd"

    if ! cargo_usable; then
        warn "cargo ${RUST_MIN} or newer not found, so the memory daemon cannot be built."
        warn "The assistant still answers, but it forgets your name, your preferences and"
        warn "what you are working on at every logout, and nothing on screen says so."
        warn "Install a Rust toolchain, then re-run: ./setup install --only-setups"
        return 0
    fi

    if ! memd_source; then
        warn "no koompi-agent-memd source; the assistant will have no long-term memory."
        warn "Clone $MEMD_REPO_URL beside this checkout, then re-run: ./setup install --only-setups"
        return 0
    fi
    info "building from $MEMD_SRC"

    # dry run: the clone above was only printed, so the dir may not exist yet
    if [[ "$DRY_RUN" == true && ! -d "$MEMD_SRC" ]]; then
        info "would build in $MEMD_SRC once it is cloned"
    else
        run_in_dir "$MEMD_SRC" cargo build --release --locked --target-dir "$build_root"
    fi
    if [[ "$DRY_RUN" != true && ! -x "$binary" ]]; then
        warn "koompi-agent-memd did not build; the assistant will have no long-term memory"
        return 0
    fi
    run install -Dm755 "$binary" "$XDG_BIN_HOME/koompi-agent-memd"
    manifest_add "$XDG_BIN_HOME/koompi-agent-memd"
    verify_agent_memory "$XDG_BIN_HOME/koompi-agent-memd"
}

# The daemon has no --version: it speaks NDJSON on stdio and announces itself with
# an id:0 ready banner once the embedding model is loaded. Asking it for that
# banner is the only check that proves the thing the shell will do actually works,
# so it is worth the one cold start.
verify_agent_memory() {
    local bin="$1" db_dir banner
    [[ "$DRY_RUN" == true ]] && { info "would run $bin once to check it answers"; return 0; }

    # a private dir, not a predicted name: sqlite also leaves -wal/-shm siblings
    db_dir="$(mktemp -d "${TMPDIR:-/tmp}/koompi-memd-check.XXXXXX")" || { warn "cannot create a scratch directory to check koompi-agent-memd"; return 0; }
    info "starting it once to see that it answers; a first run also fetches the embedding model (~100 MB)"
    banner="$(KOOMPI_AGENT_MEMORY_DB="$db_dir/memory.db" KOOMPI_AGENT_T0_QUIET_SECS=0 KOOMPI_AGENT_T1_IDLE_SECS=0 \
        timeout 600 "$bin" < /dev/null 2>/dev/null | head -n 1)"
    rm -rf -- "${db_dir:?}"

    case "$banner" in
        *'"ok":true'*) ok "koompi-agent-memd ready: $banner" ;;
        "")            warn "koompi-agent-memd is installed but printed no ready banner; the assistant will have no memory."
                       warn "Run it by hand to see why: $bin < /dev/null" ;;
        *)             warn "koompi-agent-memd answered, but not with a ready banner: $banner" ;;
    esac
}
