# shellcheck shell=bash
# Sourced by sdata/install/apps.sh. Debian and Ubuntu.
#
# Two of the applications are proprietary browsers that neither archive ships,
# so their vendor repositories are added here. Both are the official ones and
# both are pinned to their own keyring with signed-by, so neither key can sign
# for anything else in the system's sources.

have apt-get || die "no apt-get; sdata/dist-debian is for Debian and Ubuntu"

DEBIAN_FRONTEND=noninteractive
export DEBIAN_FRONTEND

# Set by install-deps.sh when the dependency step ran first, to trixie-backports
# on Debian 13. With --only-apps that never happened, and it stays empty: no
# application here lives in backports.
APT_PIN_SUITE="${APT_PIN_SUITE:-}"

# Likewise these two, so --only-apps works on its own.
if ! declare -F debian_install >/dev/null; then
    debian_read_list() {
        local f="$REPO_ROOT/sdata/dist-debian/$1"
        [[ -f "$f" ]] || return 0
        sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]*$//' "$f"
    }
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
        [[ -n "$APT_PIN_SUITE" ]] && apt_args+=(-t "$APT_PIN_SUITE")
        run sudo apt-get "${apt_args[@]}" "${available[@]}"
    }
fi

# dearmor rather than trusting the .asc directly: apt only accepts a binary
# keyring at signed-by, and a key dropped in /etc/apt/trusted.gpg.d would be
# trusted for every repository in the system rather than just this one.
# Brave already publishes its keyring dearmored; gpg --dearmor passes binary
# input straight through, so the same path handles both vendors.
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
