# shellcheck shell=bash
# Sourced by sdata/install/apps.sh. Debian and Ubuntu.
#
# Two proprietary browsers neither archive ships, so their official vendor
# repositories are added here, each pinned to its own keyring with signed-by so no
# key can sign for anything else in the system's sources.

have apt-get || die "no apt-get; sdata/dist-debian is for Debian and Ubuntu"

DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND

# Set by install-deps.sh when the dependency step ran first, to trixie-backports
# on Debian 13. With --only-apps that never happened, and it stays empty: no
# application here lives in backports.
APT_PIN_SUITE="${APT_PIN_SUITE:-}"

# debian_read_list and debian_install, so --only-apps works on its own. This
# file used to carry its own copy of both, which is how it kept the apt-cache
# show filter after install-deps.sh had been fixed.
# shellcheck source=sdata/lib/debian.sh
source "$REPO_ROOT/sdata/lib/debian.sh"

# dearmor because apt only accepts a binary keyring at signed-by, and a key in
# /etc/apt/trusted.gpg.d would be trusted for every repository. Brave already
# publishes dearmored; gpg --dearmor passes binary through, so one path handles both.
debian_add_vendor_repo() {
    local name="$1" key_url="$2" line="$3"
    local keyring="/usr/share/keyrings/${name}.gpg"
    [[ -f "/etc/apt/sources.list.d/${name}.list" ]] && return 0
    local tmp
    tmp="$(mktemp)"
    if ! _fetch "$key_url" "$tmp"; then
        warn "could not fetch the ${name} signing key; skipping that repository"
        rm -f "$tmp"
        return 1
    fi
    printf '%s     $ install %s%s\n' "${C_DIM}" "$keyring" "${C_RST}"
    if [[ "$DRY_RUN" != true ]]; then
        gpg --dearmor < "$tmp" | sudo tee "$keyring" >/dev/null || {
            warn "could not write $keyring; skipping ${name}"; rm -f "$tmp"; return 1; }
        sudo chmod 0644 "$keyring"
    fi
    rm -f "$tmp"
    sudo_write "/etc/apt/sources.list.d/${name}.list" \
        "deb [arch=${DEB_ARCH} signed-by=${keyring}] ${line}"
}

# _fetch and install_zed.
source "$REPO_ROOT/sdata/lib/from-source.sh"

DEB_ARCH="$(dpkg --print-architecture)"

step "Debian/Ubuntu: browser repositories"
# Google publishes amd64 and arm64 only; Brave publishes amd64 only. On any
# other architecture the repository would resolve to nothing, and apt would
# print an error on every update from then on.
case "$DEB_ARCH" in
    amd64|arm64)
        debian_add_vendor_repo google-chrome \
            https://dl.google.com/linux/linux_signing_key.pub \
            "https://dl.google.com/linux/chrome/deb/ stable main" || true
        ;;
    *) warn "no Google Chrome build for ${DEB_ARCH}; skipping that repository" ;;
esac
case "$DEB_ARCH" in
    amd64)
        debian_add_vendor_repo brave-browser \
            https://brave-browser-apt-release.s3.brave.com/brave-browser-archive-keyring.gpg \
            "https://brave-browser-apt-release.s3.brave.com/ stable main" || true
        ;;
    *) warn "no Brave build for ${DEB_ARCH}; skipping that repository" ;;
esac

run sudo apt-get update

step "Debian/Ubuntu: installing applications"
mapfile -t _debian_apps < <(debian_read_list packages-apps.list)
info "${#_debian_apps[@]} applications"
debian_install "${_debian_apps[@]}"
unset _debian_apps

step "Debian/Ubuntu: the applications no archive carries"
install_zed
