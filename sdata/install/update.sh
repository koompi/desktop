# shellcheck shell=bash
# Sourced by ./setup. `update` for a machine that already runs KOOMPI.
#
# This is deliberately not a synonym for `install`. Install answers "set this
# machine up"; update answers "I already run KOOMPI, give me what changed", and
# the difference shows up in three places: it pulls the checkout first, it does
# not ask about the application set again, and it reloads the running session at
# the end instead of telling you to log out.
#
# Everything it calls is idempotent, so the cost of an update with nothing
# outstanding is a git fetch and a handful of rsyncs that write nothing.

# A pull that would clobber local edits is the one thing an updater must never
# do quietly: the hypr/custom slots exist precisely so people edit this tree.
update_pull() {
    step "Updating the checkout"

    if ! have git || [[ ! -d "$REPO_ROOT/.git" ]]; then
        info "not a git checkout; updating from the files already here"
        return 0
    fi

    local branch
    branch="$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD 2>/dev/null)" || branch=''
    if [[ -z "$branch" || "$branch" == HEAD ]]; then
        warn "detached HEAD; not pulling. Check out a branch to track upstream."
        return 0
    fi

    if [[ -n "$(git -C "$REPO_ROOT" status --porcelain)" ]]; then
        warn "the checkout has uncommitted changes, so pulling could lose them"
        info "commit or stash them, then re-run; installing from the tree as it stands"
        return 0
    fi

    local before after
    before="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    run git -C "$REPO_ROOT" pull --ff-only
    run git -C "$REPO_ROOT" submodule update --init --recursive
    after="$(git -C "$REPO_ROOT" rev-parse HEAD)"

    if [[ "$before" == "$after" ]]; then
        ok "already up to date at ${before:0:8}"
    else
        ok "updated ${before:0:8} -> ${after:0:8}"
        info "$(git -C "$REPO_ROOT" log --oneline "$before..$after" | wc -l) new commit(s)"
    fi
}

run_update() {
    step "KOOMPI desktop update"
    detect_distro
    # An unrecognised distro can still take the config; only the package step
    # has to stand down. The application set is not offered on an update at all.
    report_distro || DO_DEPS=false

    update_pull

    if $DO_DEPS || $DO_SETUPS; then
        sudo_start
        trap 'sudo_stop' EXIT INT TERM
    fi

    # Dependencies, because an update can introduce a new one, and the recipe
    # already skips everything that is satisfied.
    $DO_DEPS && install_deps

    # The application set is NOT re-offered. Someone updating has already
    # answered that question, and an updater that keeps proposing to install
    # apps you declined is an updater people stop running. `./setup install
    # --only-apps` is still there for anyone who changes their mind.

    $DO_SETUPS && run_setups
    $DO_FILES  && install_files

    record_repo_path

    sudo_stop
    trap - EXIT INT TERM

    reload_session

    step "Done"
    cat <<EOF
  KOOMPI is up to date.
  Your ${C_BOLD}~/.config/hypr/custom/${C_RST} overrides were left untouched.
EOF
}
