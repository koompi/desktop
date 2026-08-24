# shellcheck shell=bash
# Sourced by sdata/install/deps.sh. Arch Linux and derivatives.
#
# Dependency metapackages only. koompi-hyprland-config, koompi-shell,
# koompi-session and the koompi-desktop-* editions are deliberately left out:
# ./setup installs that content into $HOME, and having both gives two copies of the
# shell fighting over the same paths. Full OS image: sdata/dist-arch/iso/koompi/.

have pacman || die "no pacman; sdata/dist-arch is for Arch and its derivatives"

# arch_install_paru and arch_install_pkgbuild, shared with install-apps.sh.
# shellcheck source=sdata/lib/arch.sh
source "$REPO_ROOT/sdata/lib/arch.sh"

# Dependency metas, in dependency order. A meta's depends[] go in through paru,
# which only knows the repos and the AUR, so anything built from this directory
# has to be listed here ahead of whatever names it. tests/test_arch_local_dep_order.sh
# fails if one is missing or listed too late.
ARCH_DEP_PKGBUILDS=(
    koompi-basic
    koompi-audio
    koompi-backlight
    ttf-koompi-star
    koompi-fonts-themes
    koompi-kde
    koompi-portal
    koompi-python
    koompi-screencapture
    koompi-toolkit
    koompi-widgets
    koompi-hyprland
    koompi-quickshell-git
    koompi-microtex-git
    koompi-bibata-modern-classic-bin
)

# Package names from the pre-KOOMPI era. Left installed they sit as orphans and,
# worse, the -git builds shadow the repo versions the metas now pull in.
arch_drop_deprecated() {
    local superseded=(
        illogical-impulse-{microtex,pymyc-aur,oneui4-icons-git}
        illogical-impulse-{quickshell-git,audio,backlight,basic,bibata-modern-classic-bin}
        illogical-impulse-{fonts-themes,hyprland,kde,microtex-git,portal,python}
        illogical-impulse-{screencapture,toolkit,widgets}
        matugen-bin hyprland-qtutils
        {quickshell,hyprutils,hyprpicker,hyprlang,hypridle,hyprland-qt-support}-git
        {hyprland-qtutils,hyprlock,xdg-desktop-portal-hyprland,hyprcursor}-git
        {hyprwayland-scanner,hyprland}-git
    )
    # Naming the -debug siblings is the only way they go. makepkg's
    # create_debug_package() empties the split package's conflicts, provides and
    # replaces, so no conflicts= in a successor can displace one. Names that are not
    # installed cost nothing - arch_exact_installed_packages prints installed names only.
    local stale=("${superseded[@]}" "${superseded[@]/%/-debug}")
    local exact
    exact="$(arch_exact_installed_packages "${stale[@]}")" ||
        die "could not read the installed pacman package database"
    local present=()
    [[ -z "$exact" ]] || mapfile -t present <<< "$exact"
    (( ${#present[@]} )) || return 0
    warn "removing ${#present[@]} superseded package(s): ${present[*]}"
    # -Rdd: they are replaced by the metas installed immediately after, so the
    # dependency check would refuse a removal that is in fact safe.
    run sudo pacman -Rdd --noconfirm "${present[@]}"
}

# Ahead of the survey, because it is a migration that has to happen on a machine
# that is otherwise complete, and because removing a shadowing -git build is
# exactly the kind of thing that leaves a metapackage's dependencies unsatisfied.
arch_drop_deprecated

# Work out what is actually missing before touching anything else. On a machine
# that is already up to date this costs a handful of local database reads and
# lets the whole step fall through - no upgrade, no paru, no rebuilds.
mapfile -t _koompi_pending < <(arch_pending_pkgbuilds "${ARCH_DEP_PKGBUILDS[@]}")

if (( ${#_koompi_pending[@]} == 0 )); then
    ok "all ${#ARCH_DEP_PKGBUILDS[@]} dependency metapackages are already installed"
else
    info "${#_koompi_pending[@]} of ${#ARCH_DEP_PKGBUILDS[@]} metapackage(s) need work: ${_koompi_pending[*]}"

    # Only now is the upgrade worth its cost. It still has to happen before any
    # AUR build: building against a half-upgraded system is how Arch breaks.
    step "Arch: refreshing packages"
    sudo_refresh
    run sudo pacman -Syu --noconfirm

    arch_install_paru

    for _koompi_pkg in "${_koompi_pending[@]}"; do
        step "Arch: $_koompi_pkg"
        # Unchecked, a metapackage that failed to build leaves the loop building
        # the ones after it against the version it was supposed to replace, and
        # the run still ends with "dependencies installed".
        arch_install_pkgbuild "$_koompi_pkg" ||
            die "$_koompi_pkg failed to install; fix that before re-running"
    done
    unset _koompi_pkg
fi
unset _koompi_pending

# ~600 KiB itself, but on a machine without KDE it drags in ~600 MiB of Plasma.
# Only worth it for media-position reporting out of Firefox.
if ! pacman -Qq plasma-browser-integration >/dev/null 2>&1; then
    if confirm "Install plasma-browser-integration? (browser media position in the shell; pulls KDE libraries)"; then
        run sudo pacman -S --needed --noconfirm plasma-browser-integration
    fi
fi
