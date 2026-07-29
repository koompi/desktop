# shellcheck shell=bash
# Sourced by sdata/install/apps.sh. Fedora 43 and later.
#
# Two of the applications are proprietary browsers that Fedora will not ship,
# so their vendor repositories are added here. Both are the official ones, both
# are signed, and each is added as its own file under /etc/yum.repos.d so
# removing it later is one `rm`.

have dnf || die "no dnf; sdata/dist-fedora is for Fedora and its derivatives"

# Google publishes a repo definition through Fedora's own
# fedora-workstation-repositories package, which is preferable to writing the
# file ourselves: it is maintained by Fedora and disabled until asked for.
fedora_enable_chrome_repo() {
    rpm -q google-chrome-stable >/dev/null 2>&1 && return 0
    run sudo dnf install -y fedora-workstation-repositories
    run sudo dnf config-manager setopt google-chrome.enabled=1
}

fedora_enable_brave_repo() {
    rpm -q brave-browser >/dev/null 2>&1 && return 0
    [[ -f /etc/yum.repos.d/brave-browser.repo ]] && return 0
    run sudo rpm --import https://brave-browser-rpm-release.s3.brave.com/brave-core.asc
    run sudo dnf config-manager addrepo \
        --from-repofile=https://brave-browser-rpm-release.s3.brave.com/brave-browser.repo
}

step "Fedora: browser repositories"
fedora_enable_chrome_repo
fedora_enable_brave_repo

step "Fedora: installing applications"
mapfile -t _fedora_apps < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]*$//' \
    "$REPO_ROOT/sdata/dist-fedora/packages-apps.list")
info "${#_fedora_apps[@]} applications"
# Same reasoning as the dependency step: one program Fedora has dropped should
# cost that program, not the install. ./setup doctor reports what landed.
run sudo dnf install -y --setopt=install_weak_deps=False --skip-unavailable "${_fedora_apps[@]}"
unset _fedora_apps

step "Fedora: the applications no repository carries"
source "$REPO_ROOT/sdata/lib/from-source.sh"
install_zed
