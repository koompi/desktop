# shellcheck shell=bash
# Sourced by ./setup. `update` for a machine that already runs KOOMPI.
#
# Not a synonym for `install`: it pulls the checkout first, does not ask about the
# application set again, and reloads the running session at the end instead of
# telling you to log out. Everything it calls is idempotent.

# prod-hd only ever fast-forwards from main and is never authored on, so its
# history is a prefix of main's and the pull below stays an ordinary --ff-only
PROD_BRANCH='prod-hd'

follow_prod_wanted() {
    case "${KOOMPI_FOLLOW_PROD:-}" in
        0|false|no) return 1 ;;
        1|true|yes) return 0 ;;
    esac
    case "$(git -C "$REPO_ROOT" config --get koompi.followprod 2>/dev/null)" in
        0|false|no) return 1 ;;
    esac
    return 0
}

origin_is_koompi() {
    local url
    url="$(git -C "$REPO_ROOT" remote get-url origin 2>/dev/null)" || return 1
    # koompi-desktop: pre-rename url, still origin on machines installed before it
    [[ "$url" =~ [:/]koompi/koompi-(hd|desktop)(\.git)?/?$ ]]
}

# managed = the checkout this machine updates from, carrying nothing of its own.
# anything else is a tree somebody works in; hijacking its branch is worse than
# doing nothing, so it is left where it is and told why. always returns 0: a
# checkout that cannot move is still one to pull.
follow_prod_branch() {
    local branch="$1"
    local -a checkout=(checkout "$PROD_BRANCH")

    [[ "$branch" == "$PROD_BRANCH" ]] && return 0

    if ! follow_prod_wanted; then
        info "staying on '$branch': following $PROD_BRANCH is switched off here"
        return 0
    fi
    if [[ "$branch" != main ]]; then
        info "on '$branch', not main: leaving this checkout on its own branch"
        return 0
    fi
    if ! origin_is_koompi; then
        info "origin is not the KOOMPI repo: leaving this checkout on '$branch'"
        return 0
    fi
    if ! git -C "$REPO_ROOT" rev-parse --abbrev-ref '@{u}' >/dev/null 2>&1; then
        info "'$branch' tracks no upstream: leaving this checkout on it"
        return 0
    fi
    if ! git -C "$REPO_ROOT" merge-base --is-ancestor HEAD '@{u}' 2>/dev/null; then
        info "'$branch' carries commits upstream does not have: leaving this checkout on it"
        return 0
    fi

    # not pushed yet, or offline: today's behaviour, and no error text at them
    git -C "$REPO_ROOT" ls-remote --exit-code --heads origin "$PROD_BRANCH" >/dev/null 2>&1 \
        || return 0

    if [[ "$DRY_RUN" == true ]]; then
        info "(dry run: this checkout would move from '$branch' to $PROD_BRANCH)"
        return 0
    fi

    # install.sh clones --depth 1 --branch main: prod-hd is in neither the
    # refspec nor the history
    if ! git -C "$REPO_ROOT" config --get-all remote.origin.fetch 2>/dev/null \
        | grep -qxF "+refs/heads/$PROD_BRANCH:refs/remotes/origin/$PROD_BRANCH"; then
        git -C "$REPO_ROOT" config --add remote.origin.fetch \
            "+refs/heads/$PROD_BRANCH:refs/remotes/origin/$PROD_BRANCH" \
            || { warn "could not track $PROD_BRANCH here; staying on '$branch'"; return 0; }
    fi
    try git -C "$REPO_ROOT" fetch --quiet origin \
        "+refs/heads/$PROD_BRANCH:refs/remotes/origin/$PROD_BRANCH" \
        || { warn "could not fetch $PROD_BRANCH; staying on '$branch'"; return 0; }

    if git -C "$REPO_ROOT" rev-parse --verify --quiet "refs/heads/$PROD_BRANCH" >/dev/null; then
        # a local prod-hd upstream's does not contain is somebody's own branch
        if ! git -C "$REPO_ROOT" merge-base --is-ancestor \
                "refs/heads/$PROD_BRANCH" "refs/remotes/origin/$PROD_BRANCH" 2>/dev/null; then
            info "the local '$PROD_BRANCH' here is not upstream's: leaving this checkout on '$branch'"
            return 0
        fi
    else
        checkout=(checkout -b "$PROD_BRANCH" --track "origin/$PROD_BRANCH")
    fi

    # a shallow graft cuts the parent a later ff-only pull needs
    if [[ "$(git -C "$REPO_ROOT" rev-parse --is-shallow-repository 2>/dev/null)" == true ]]; then
        try git -C "$REPO_ROOT" fetch --quiet --unshallow origin \
            || { warn "could not deepen this shallow checkout; staying on '$branch'"; return 0; }
    fi

    try git -C "$REPO_ROOT" "${checkout[@]}" \
        || { warn "could not check out $PROD_BRANCH; staying on '$branch'"; return 0; }
    ok "moved from '$branch' to $PROD_BRANCH, the line KOOMPI releases from"
    return 0
}

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

    follow_prod_branch "$branch"

    local before after pulled=false skipped=false reply
    before="$(git -C "$REPO_ROOT" rev-parse HEAD)"
    # Not routed through run(): its skip answer returns 0, which used to fall
    # through to a before/after comparison that reported "already up to date"
    # for an update that never pulled. The pull's real outcome is tracked here
    # and reported as what it is.
    printf '%s     $ %s%s\n' "${C_DIM}" "git -C \"$REPO_ROOT\" pull --ff-only" "${C_RST}"
    if [[ "$DRY_RUN" == true ]]; then
        printf '  (dry run: nothing is pulled)\n'
        return 0
    fi
    until git -C "$REPO_ROOT" pull --ff-only; do
        err "command failed: git pull"
        if [[ "$ASSUME_YES" == true ]]; then
            die "aborting (--yes means no interactive recovery)"
        fi
        read -rp "  [r]etry / [s]kip / [a]bort (default abort): " reply
        case "$reply" in
            r|R) continue ;;
            s|S) warn "skipped: git pull"; skipped=true; break ;;
            *)   die "aborted" ;;
        esac
    done

    if [[ "$skipped" != true ]]; then
        pulled=true
        run git -C "$REPO_ROOT" submodule update --init --recursive
    fi
    after="$(git -C "$REPO_ROOT" rev-parse HEAD)"

    if [[ "$pulled" != true ]]; then
        warn "not pulled; installing from the tree as it stands (${before:0:8})"
    elif [[ "$before" == "$after" ]]; then
        ok "already up to date at ${before:0:8}"
    else
        ok "updated ${before:0:8} -> ${after:0:8}"
        info "$(git -C "$REPO_ROOT" log --oneline "$before..$after" | wc -l) new commit(s)"
    fi
}

# The update engine shipped with this checkout: it owns the defaults dump and
# the three-way config merge, so both routes (this one and packaged koompi
# update) run identical logic from one installed place.
UPDATE_TOOL="$REPO_ROOT/dots/.local/share/koompi/libexec/update"

# Defaults migration for the from-git route. Old = this checkout BEFORE the
# pull, which is exactly what every installed copy was last written against;
# new = the same tree now. Dumps run through libexec/update; on any failure to
# obtain either side we skip loudly rather than guess.
migrate_config_defaults() {
    local pre_dump="$1"
    local post_dump

    if [[ ! -x "$UPDATE_TOOL" ]]; then
        warn "no update engine at $UPDATE_TOOL; skipping the config merge rather than guessing"
        return 1
    fi
    if [[ ! -s "$pre_dump" ]]; then
        warn "old defaults were not captured before the pull; skipping the config merge rather than guessing"
        return 1
    fi

    # The engine prints its own "Migrating config defaults" step.
    post_dump="$(mktemp "${TMPDIR:-/tmp}/koompi-post.XXXXXX")"
    if ! "$UPDATE_TOOL" dump-defaults "$REPO_ROOT/dots/.config/quickshell/koompi" "$post_dump"; then
        rm -f "$post_dump"
        warn "new defaults could not be dumped; skipping the config merge rather than guessing"
        return 1
    fi

    KOOMPI_UPDATE_DRY_RUN="$DRY_RUN" "$UPDATE_TOOL" apply-defaults-migration \
        "$pre_dump" "$post_dump" true || { rm -f "$post_dump"; return 1; }

    # Baseline for the next update, whichever route it takes.
    if [[ "$DRY_RUN" != true ]]; then
        mkdir -p "$KOOMPI_STATE_DIR"
        cp -a -- "$post_dump" "${KOOMPI_STATE_DIR}/config-defaults.json.tmp" \
            && mv -f -- "${KOOMPI_STATE_DIR}/config-defaults.json.tmp" \
                        "${KOOMPI_STATE_DIR}/config-defaults.json"
    fi
    rm -f "$post_dump"
}

run_update() {
    step "KOOMPI desktop update"
    detect_distro
    # An unrecognised distro can still take the config; only the package step
    # has to stand down. The application set is not offered on an update at all.
    report_distro || DO_DEPS=false

    # Capture the defaults the user is running NOW, before the checkout moves.
    local pre_defaults=""
    if have qs && [[ -x "$UPDATE_TOOL" ]]; then
        pre_defaults="$(mktemp "${TMPDIR:-/tmp}/koompi-pre.XXXXXX")"
        "$UPDATE_TOOL" dump-defaults \
            "$REPO_ROOT/dots/.config/quickshell/koompi" "$pre_defaults" \
            || { warn "could not dump the pre-update defaults"; pre_defaults=""; }
    elif [[ ! -x "$UPDATE_TOOL" ]]; then
        warn "no update engine at $UPDATE_TOOL; config default changes cannot be migrated this run"
    fi

    update_pull

    if $DO_DEPS || $DO_SETUPS; then
        sudo_start
        trap 'sudo_stop' EXIT INT TERM
    fi

    # Dependencies, because an update can introduce a new one, and the recipe
    # already skips everything that is satisfied. Stopping here on failure is
    # the point: the rest of an update copies config that expects the packages
    # this step was meant to provide.
    if $DO_DEPS; then
        install_deps || die "dependency installation failed; not continuing"
    fi

    # The application set is NOT re-offered. Someone updating has already
    # answered that question, and an updater that keeps proposing to install
    # apps you declined is an updater people stop running. `./setup install
    # --only-apps` is still there for anyone who changes their mind.

    $DO_SETUPS && run_setups
    if $DO_FILES; then
        install_files || die "config file installation failed; not continuing"
    fi
    # its units ship from dots/, must exist before enabling
    $DO_SETUPS && setup_services

    migrate_config_defaults "$pre_defaults"
    [[ -n "$pre_defaults" ]] && rm -f "$pre_defaults"

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
