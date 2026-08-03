# shellcheck shell=bash
# Shared Arch helpers, sourced by both dist-arch recipes - which is why this file
# exists: the recipes run their work on being sourced, so one cannot source the
# other to borrow a function. Nothing here has a side effect at source time.

# A targeted `pacman -Qq <name>` is not an exact-name check: it resolves provides=,
# so asking for `quickshell-git` can print `illogical-impulse-quickshell-git`, and
# passing that alias to `pacman -R` fails with "target not found".
arch_exact_installed_packages() {
    local installed candidate
    installed="$(pacman -Qq)" || return 1

    for candidate in "$@"; do
        if grep -Fxq -- "$candidate" <<< "$installed"; then
            printf '%s\n' "$candidate"
        fi
    done
    return 0
}

arch_install_yay() {
    have yay && return 0
    info "yay not found; building it (needed for the AUR dependencies)"
    local build
    build="$(mktemp -d)"
    run sudo pacman -S --needed --noconfirm base-devel git
    run git clone --depth 1 https://aur.archlinux.org/yay-bin.git "$build"
    run_in_dir "$build" makepkg -si --noconfirm
    rm -rf "$build"
}

# Read pkgname and pkgver-pkgrel out of a PKGBUILD without leaking the variables into
# the caller. No koompi-* meta has a pkgver() - the -git ones pin a _commit and bump
# pkgrel by hand - so the file says exactly what a build would produce.
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
        local -a wanted
        mapfile -t wanted <<< "$missing"
        # yay calls sudo on its own account, part-way through a resolve it does
        # not report progress for. Take the prompt here, at a boundary.
        sudo_refresh
        run yay -S --needed --noconfirm --asdeps "${wanted[@]}"
    fi

    # With `debug` in /etc/makepkg.conf, the Arch default, every meta also yields a
    # -debug split package. That sibling is a package like any other: it can conflict
    # with a predecessor's -debug and has to be installed alongside its parent.
    local -a produced=()
    mapfile -t produced < <(cd -- "$dir" && makepkg --packagelist 2>/dev/null)
    (( ${#produced[@]} )) || { err "cannot read the package list for $1"; return 1; }

    # -A ignore arch, -f rebuild, -s pull build deps. No -i on purpose: makepkg -i sudoes
    # from inside the build, so the prompt lands mid-job with --noconfirm holding the
    # terminal, and a failed install there is only a WARNING on exit status 0. Installing
    # from here refreshes sudo at a step boundary and makes a file conflict visible.
    run_in_dir "$dir" makepkg -Afs --noconfirm || return 1

    if [[ "$DRY_RUN" == true ]]; then
        info "would install ${produced[*]##*/}"
        return 0
    fi

    # --packagelist names the debug package whether or not the build had
    # symbols to split out, so install what is on disk rather than what was
    # predicted.
    local -a built=() artefact
    for artefact in "${produced[@]}"; do
        [[ -f "$artefact" ]] && built+=("$artefact")
    done
    (( ${#built[@]} )) || { err "$1 built no package to install"; return 1; }

    sudo_refresh
    run sudo pacman -U --needed --noconfirm "${built[@]}"
}
