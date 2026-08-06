# shellcheck shell=bash
# Shared apt helpers, sourced by both dist-debian recipes - which is why this
# file exists: the recipes run their work on being sourced, so one cannot source
# the other to borrow a function, and install-apps.sh had grown its own copy of
# debian_install carrying the bug fixed below. Nothing here has a side effect at
# source time. debian_install reads APT_PIN_SUITE, which each recipe sets.

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

debian_read_list() {
    local f="$REPO_ROOT/sdata/dist-debian/$1"
    [[ -f "$f" ]] || return 0
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]*$//' "$f"
}

# apt fails the whole transaction on one unknown package name, which on a
# derivative is a near certainty. Ask what apt would actually install first and
# report the rest instead of aborting.
debian_install() {
    local -a wanted=("$@") available=() missing=()
    local pkg
    for pkg in "${wanted[@]}"; do
        if debian_candidate "$pkg" >/dev/null; then
            available+=("$pkg")
        else
            missing+=("$pkg")
        fi
    done
    if (( ${#missing[@]} )); then
        warn "not available on this release, skipping: ${missing[*]}"
    fi
    (( ${#available[@]} )) || return 0

    local -a apt_args=(install -y --no-install-recommends)
    # Backported packages are lower priority than main by design, so they need
    # naming explicitly or apt quietly installs nothing.
    [[ -n "${APT_PIN_SUITE:-}" ]] && apt_args+=(-t "$APT_PIN_SUITE")
    run sudo apt-get "${apt_args[@]}" "${available[@]}"
}
