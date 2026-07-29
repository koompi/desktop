# shellcheck shell=bash
# Sourced by ./setup. Maps /etc/os-release onto one of the OS groups that has a
# sdata/dist-<group>/install-deps.sh.
#
# Supported groups: arch, fedora, debian (Ubuntu and its derivatives arrive here
# through ID_LIKE). Anything else stops the dependency step rather than guessing
# a package manager, because a wrong guess leaves a half-installed system.

detect_distro() {
    local os_release=/etc/os-release
    # Lets CI and `setup checkdeps` pretend to be another distro.
    [[ -n "${KOOMPI_OS_RELEASE:-}" ]] && os_release="${KOOMPI_OS_RELEASE}"
    [[ -r "$os_release" ]] || die "cannot read $os_release, so the distro cannot be identified"

    OS_DISTRO_ID="$(awk -F= '/^ID=/        { gsub(/["\047]/,"",$2); print tolower($2); exit }' "$os_release")"
    OS_DISTRO_LIKE="$(awk -F= '/^ID_LIKE=/ { gsub(/["\047]/,"",$2); print tolower($2); exit }' "$os_release")"
    OS_VERSION_ID="$(awk -F= '/^VERSION_ID=/ { gsub(/["\047]/,"",$2); print $2; exit }' "$os_release")"
    export OS_DISTRO_ID OS_DISTRO_LIKE OS_VERSION_ID

    OS_GROUP_ID=''
    OS_GROUP_EXACT=true
    local id
    for id in "$OS_DISTRO_ID" $OS_DISTRO_LIKE; do
        case "$id" in
            arch|archlinux|koompi)   OS_GROUP_ID=arch   ;;
            fedora|rhel|centos)      OS_GROUP_ID=fedora ;;
            debian|ubuntu)           OS_GROUP_ID=debian ;;
            *)                       continue ;;
        esac
        [[ "$id" == "$OS_DISTRO_ID" ]] || OS_GROUP_EXACT=false
        break
    done
    export OS_GROUP_ID OS_GROUP_EXACT

    OS_ARCH="$(uname -m)"
    export OS_ARCH
}

report_distro() {
    info "distro: ${OS_DISTRO_ID:-unknown} ${OS_VERSION_ID:-} (ID_LIKE: ${OS_DISTRO_LIKE:-none})"
    info "arch:   ${OS_ARCH}"
    if [[ -z "$OS_GROUP_ID" ]]; then
        warn "no dependency recipe for this distro."
        warn "Supported: Arch (and derivatives), Fedora, Debian, Ubuntu."
        warn "Run './setup install --no-deps' to install the config files only,"
        warn "then install the packages in docs/dependencies.md by hand."
        return 1
    fi
    info "package recipe: sdata/dist-${OS_GROUP_ID}"
    if [[ "$OS_GROUP_EXACT" != true ]]; then
        warn "matched via ID_LIKE, not an exact match. Package names may differ on this derivative."
    fi
    if [[ "$OS_ARCH" != x86_64 && "$OS_ARCH" != aarch64 ]]; then
        warn "only x86_64 and aarch64 are tested; expect missing packages on ${OS_ARCH}."
    fi
    return 0
}
