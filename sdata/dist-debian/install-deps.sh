# shellcheck shell=bash
# Sourced by sdata/install/deps.sh. Debian and Ubuntu.
#
# Both distros package the Hyprland stack and quickshell, but only in recent
# releases and, on Debian 13, only in backports. Older releases are refused
# rather than half-installed - see debian_check_release() for why each one is
# out. What no archive carries (the fonts, adw-gtk3, uv, matugen on Debian,
# hyprsunset on Ubuntu) comes from sdata/lib/from-source.sh.

have apt-get || die "no apt-get; sdata/dist-debian is for Debian and Ubuntu"

DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND

APT_PIN_SUITE=''   # set to trixie-backports on Debian 13
IS_UBUNTU=false
[[ "$OS_DISTRO_ID" == ubuntu || "$OS_DISTRO_LIKE" == *ubuntu* ]] && IS_UBUNTU=true

# VERSION_ID only means what we think it means on Debian and Ubuntu themselves.
# A derivative numbers its own releases - Linux Mint 22 is Ubuntu 24.04 - so
# refusing on the number would give Mint the wrong answer in both directions.
# This only handles the exact matches, and every distro is checked properly
# against the real package version later, in debian_require_hyprland().
debian_check_release() {
    local v="${OS_VERSION_ID:-0}"
    local major="${v%%.*}"

    if [[ "$OS_DISTRO_ID" == ubuntu ]]; then
        # 24.04: no Hyprland at all, Qt 6.4.2 against quickshell's 6.6 floor,
        # libwayland 1.22.0 against Hyprland's 1.22.90 - getting there means
        # rebuilding the Wayland stack.
        # 25.10: Hyprland 0.41, too old for this config, and EOL since July 2026.
        if (( major > 0 && major < 26 )); then
            err "Ubuntu ${v} cannot run this desktop."
            err "24.04 has no Hyprland and Qt 6.4 (quickshell needs 6.6+);"
            err "25.10 ships Hyprland 0.41, too old for this config, and is EOL."
            die "Ubuntu 26.04 or later is required."
        fi
    elif [[ "$OS_DISTRO_ID" == debian ]]; then
        # Debian 13 has zero hypr* packages in main; trixie-backports has the
        # whole stack including quickshell 0.3.0. 14 and sid have it in main.
        if (( major == 13 )); then
            APT_PIN_SUITE=trixie-backports
        elif (( major > 0 && major < 13 )); then
            die "Debian ${v} is too old; 13 (trixie) with backports is the minimum."
        fi
    else
        info "derivative release numbering, so the package versions decide"
    fi
    return 0
}

# The real gate, and the only one a derivative sees: what version of Hyprland
# can apt actually install? This config needs 0.45 or newer, and every way of
# being too old ends here - wrong release, missing backports, a derivative that
# forked before the stack landed.
debian_require_hyprland() {
    local candidate
    candidate="$(apt-cache policy hyprland 2>/dev/null | awk '/Candidate:/ { print $2 }')"

    if [[ -z "$candidate" || "$candidate" == "(none)" ]]; then
        err "apt has no installable 'hyprland'."
        [[ -n "$APT_PIN_SUITE" ]] && err "Even with ${APT_PIN_SUITE} enabled - check that the mirror carries it."
        $IS_UBUNTU && err "On Ubuntu the compositor lives in 'universe'; check that it is enabled."
        die "cannot install the desktop without a compositor"
    fi

    # Strip the epoch and Debian revision: "1:0.55.2+ds-1~bpo13+1" -> "0.55.2".
    local ver="${candidate#*:}"
    # The '-' must stay last inside the bracket or it reads as a range.
    ver="${ver%%[+~-]*}"
    local major="${ver%%.*}"
    local rest="${ver#*.}"
    local minor="${rest%%.*}"

    if [[ ! "$major" =~ ^[0-9]+$ || ! "$minor" =~ ^[0-9]+$ ]]; then
        warn "could not read the Hyprland version from '${candidate}'; continuing"
        return 0
    fi
    if (( major == 0 && minor < 45 )); then
        err "apt offers Hyprland ${ver}; this config needs 0.45 or newer."
        err "That release is too old to run the KOOMPI shell."
        die "upgrade the distro, or add a repository with a current Hyprland"
    fi
    ok "Hyprland ${ver} available"
}

# translate-shell is in contrib on Debian and multiverse on Ubuntu, neither of
# which is enabled by default.
debian_enable_components() {
    if $IS_UBUNTU; then
        step "Ubuntu: enabling universe and multiverse"
        run sudo add-apt-repository -y universe
        run sudo add-apt-repository -y multiverse
        # quickshell, matugen and libcpptrace are not in the Ubuntu archive.
        step "Ubuntu: enabling the quickshell PPA"
        run sudo add-apt-repository -y ppa:avengemedia/danklinux
        return 0
    fi

    if [[ -n "$APT_PIN_SUITE" ]]; then
        step "Debian: enabling ${APT_PIN_SUITE}"
        info "Debian 13 keeps the whole Hyprland stack in backports, not main"
        sudo_write /etc/apt/sources.list.d/koompi-backports.list \
            "deb http://deb.debian.org/debian ${APT_PIN_SUITE} main contrib non-free non-free-firmware"
    fi
}

debian_read_list() {
    local f="$REPO_ROOT/sdata/dist-debian/$1"
    [[ -f "$f" ]] || return 0
    sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]*$//' "$f"
}

# apt fails the whole transaction on one unknown package name, which on a
# derivative is a near certainty. Ask apt-cache what it actually has first and
# report the rest instead of aborting.
debian_install() {
    local -a wanted=("$@") available=() missing=()
    local pkg
    for pkg in "${wanted[@]}"; do
        if apt-cache show "$pkg" >/dev/null 2>&1; then
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
    [[ -n "$APT_PIN_SUITE" ]] && apt_args+=(-t "$APT_PIN_SUITE")
    run sudo apt-get "${apt_args[@]}" "${available[@]}"
}

# Ubuntu packages neither hyprsunset nor its absence: the night-light feature
# just stops working. Its build deps are all in resolute universe, so building
# it is a few minutes rather than a Wayland-stack rebuild.
debian_build_hyprsunset() {
    have hyprsunset && return 0
    step "hyprsunset (not packaged on Ubuntu)"
    if ! confirm "Build hyprsunset from source? (skipping only disables night light)"; then
        warn "skipped; the blue-light filter will not work"
        return 0
    fi
    run sudo apt-get install -y --no-install-recommends \
        build-essential cmake pkgconf libwayland-dev wayland-protocols \
        libhyprutils-dev libhyprlang-dev hyprwayland-scanner hyprland-protocols
    local src
    src="$(mktemp -d)"
    run git clone --depth 1 https://github.com/hyprwm/hyprsunset "$src"
    ( cd "$src" && run cmake -B build -S . -DCMAKE_BUILD_TYPE=Release && run cmake --build build -j"$(nproc)" \
        && run sudo cmake --install build )
    rm -rf "$src"
}

#####################################################################################

debian_check_release
debian_enable_components

step "Debian/Ubuntu: refreshing packages"
run sudo apt-get update

debian_require_hyprland

step "Debian/Ubuntu: installing packages"
mapfile -t _debian_pkgs < <(debian_read_list packages.list)
if $IS_UBUNTU; then
    mapfile -t -O "${#_debian_pkgs[@]}" _debian_pkgs < <(debian_read_list packages-ubuntu.list)
else
    mapfile -t -O "${#_debian_pkgs[@]}" _debian_pkgs < <(debian_read_list packages-debian.list)
fi
info "${#_debian_pkgs[@]} packages"
debian_install "${_debian_pkgs[@]}"
unset _debian_pkgs

# quickshell links private Qt APIs and breaks on a Qt ABI bump, so it is held
# rather than left to float with the next apt upgrade.
if dpkg -s quickshell >/dev/null 2>&1; then
    run sudo apt-mark hold quickshell
    info "quickshell held; run 'sudo apt-mark unhold quickshell' before upgrading Qt"
fi

step "Debian/Ubuntu: the parts no archive carries"
source "$REPO_ROOT/sdata/lib/from-source.sh"
install_uv
have yq || install_go_yq
install_matugen
install_hyprshot
install_fonts_from_release
install_google_sans_flex
install_nerd_font
install_adw_gtk3
install_bibata_cursor
$IS_UBUNTU && debian_build_hyprsunset

# Darkly, breeze-plus, songrec and microtex are all buildable but none is on the
# critical path, and each drags in a KDE or Rust toolchain. Naming them beats
# building them behind the user's back.
warn "not installed (no package on this distro, and not built here):"
warn "  darkly      - Qt apps fall back to Fusion; the qt6ct palette still applies"
warn "  breeze-plus - some icons fall back to plain Breeze"
warn "  songrec     - the music-recognition widget will do nothing"
warn "  microtex    - LaTeX rendering in the shell is off"
warn "See docs/dependencies.md if you want them."
