# shellcheck shell=bash
# Sourced by sdata/dist-debian/install-deps.sh, which runs its work on being
# sourced and so cannot be read for its functions. Nothing here has a side
# effect at source time.

# The version apt would actually install, empty when there is none. `apt-cache
# show` is not this question: it prints a stub record for any name another
# package merely depends on, so a package sitting in a component that is not
# enabled reads as available and then takes the whole apt transaction down with
# it. That is how translate-shell, which lives only in Debian's contrib, aborted
# the install of all 112 packages.
debian_candidate() {
    local candidate
    candidate="$(apt-cache policy "$1" 2>/dev/null | awk '/Candidate:/ { print $2; exit }')"
    [[ -n "$candidate" && "$candidate" != "(none)" ]] || return 1
    printf '%s\n' "$candidate"
}
