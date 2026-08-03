# shellcheck shell=bash
# Sourced by ./setup. Routes to the recipe for the detected distro.
#
# Each sdata/dist-<group>/install-deps.sh is sourced, not executed, so it can use
# run/info/warn and see REPO_ROOT and the OS_* variables. It must leave the system
# usable if it bails.

install_deps() {
    step "Installing dependencies"

    if [[ -z "$OS_GROUP_ID" ]]; then
        die "no dependency recipe for this distro; re-run with --no-deps and install the packages in sdata/dist-arch/install-deps.sh by hand"
    fi

    local recipe="$REPO_ROOT/sdata/dist-${OS_GROUP_ID}/install-deps.sh"
    [[ -f "$recipe" ]] || die "missing recipe: $recipe"

    info "using $recipe"
    # The status matters. A recipe that bailed used to fall through to the success
    # message below, so a run could print "aborted" and "ok dependencies installed"
    # three lines apart and carry on against packages that were never built.
    # shellcheck source=/dev/null
    source "$recipe" || { err "the $OS_GROUP_ID dependency recipe failed"; return 1; }

    ok "dependencies installed"
}
