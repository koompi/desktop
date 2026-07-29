# shellcheck shell=bash
# Shared Arch helpers. Sourced by both sdata/dist-arch/install-deps.sh and
# sdata/dist-arch/install-apps.sh, which is the whole reason this file exists:
# the recipes have top-level statements and run their work on being sourced, so
# one cannot source the other just to borrow a function.
#
# Nothing here has a side effect at source time.

arch_install_yay() {
    have yay && return 0
    info "yay not found; building it (needed for the AUR dependencies)"
    local build
    build="$(mktemp -d)"
    run sudo pacman -S --needed --noconfirm base-devel git
    run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$build"
    ( cd "$build" && run makepkg -si --noconfirm )
    rm -rf "$build"
}

# Read pkgname and the full pkgver-pkgrel out of a PKGBUILD without leaking the
# variables into the caller. None of the koompi-* metas has a pkgver() function
# - the -git ones pin a _commit and bump pkgrel by hand - so what is written in
# the file is exactly what a build would produce, and comparing against it is a
# sound answer to "is this already installed?".
arch_pkgbuild_meta() {
    (
        # shellcheck source=/dev/null
        source "$1/PKGBUILD"
        # shellcheck disable=SC2154  # set by the sourced PKGBUILD
        printf '%s\n%s-%s\n' "$pkgname" "$pkgver" "$pkgrel"
    )
}

# The dependencies of a PKGBUILD that are not currently satisfied. `pacman -T`
# is the right question to ask rather than `pacman -Q`: it understands provides
# and version constraints, needs no root and touches no network, so a machine
# that is already complete answers in milliseconds.
arch_pkgbuild_missing_deps() {
    (
        depends=()
        # shellcheck source=/dev/null
        source "$1/PKGBUILD"
        (( ${#depends[@]} )) || exit 0
        pacman -T -- "${depends[@]}" 2>/dev/null
        exit 0
    )
}

# True when there is nothing left to do for this meta: the package itself is
# installed at or above the shipped version, and every dependency it names is
# satisfied. Both halves matter - the meta being installed says nothing about
# whether a dependency was removed underneath it.
arch_pkgbuild_satisfied() {
    local dir="$1" name version installed missing
    { read -r name; read -r version; } < <(arch_pkgbuild_meta "$dir")
    [[ -n "$name" && -n "$version" ]] || return 1

    installed="$(pacman -Q "$name" 2>/dev/null | cut -d' ' -f2)"
    [[ -n "$installed" ]] || return 1

    # vercmp takes exactly two operands and rejects `--`. Its output is checked
    # for being a number rather than compared directly: `[[ "" -ge 0 ]]` is true
    # in bash, so a vercmp that failed for any reason would otherwise read as
    # "already up to date" and skip a package that needs installing.
    local cmp
    cmp="$(vercmp "$installed" "$version" 2>/dev/null)"
    [[ "$cmp" =~ ^-?[0-9]+$ ]] || return 1
    (( cmp >= 0 )) || return 1

    missing="$(arch_pkgbuild_missing_deps "$dir")"
    [[ -z "$missing" ]]
}

# The subset of the given metas that still needs work, as a newline list. Used
# to decide whether the run has anything to do at all before paying for a
# system upgrade or a sudo prompt.
arch_pending_pkgbuilds() {
    local pkg dir
    for pkg in "$@"; do
        dir="$REPO_ROOT/sdata/dist-arch/$pkg"
        [[ -d "$dir" ]] || { printf '%s\n' "$pkg"; continue; }
        arch_pkgbuild_satisfied "$dir" || printf '%s\n' "$pkg"
    done
}

# yay -Bi is unreliable (end-4/dots-hyprland#581), so the PKGBUILD is sourced for
# its depends[] and those go in first, then the meta itself is built.
arch_install_pkgbuild() {
    local dir="$REPO_ROOT/sdata/dist-arch/$1"
    [[ -d "$dir" ]] || { err "no such PKGBUILD dir: $dir"; return 1; }

    if arch_pkgbuild_satisfied "$dir"; then
        ok "$1 already installed and complete"
        return 0
    fi

    # Only what is actually missing. Handing yay the whole depends[] list on a
    # machine that already has it is a full AUR resolve for no change, and
    # --asdeps would re-mark packages the user installed explicitly, quietly
    # turning them into orphan candidates for the next `pacman -Rns $(pacman -Qtdq)`.
    local missing
    missing="$(arch_pkgbuild_missing_deps "$dir")"
    if [[ -n "$missing" ]]; then
        local -a want
        mapfile -t want <<< "$missing"
        run yay -S --needed --noconfirm --asdeps "${want[@]}"
    fi

    # -A ignore the arch field, -f rebuild, -s pull build deps, -i install.
    # -f stays: without it makepkg errors out on a leftover tarball from an
    # earlier attempt. The cost it used to carry is gone now that this line is
    # only reached when the meta genuinely needs building.
    ( cd "$dir" && run makepkg -Afsi --noconfirm --needed )
}
