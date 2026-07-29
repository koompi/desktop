# shellcheck shell=bash
# Sourced by sdata/install/deps.sh. Fedora 43 and later.
#
# Everything the desktop needs is packaged: Fedora proper carries quickshell and
# matugen, and four COPRs carry the Hyprland stack, the KOOMPI fonts, Darkly and
# starship. Nothing is built from source here.
#
# This deliberately does NOT reproduce upstream's prebuilt-RPM mechanism, which
# downloaded quickshell and matugen from a GitHub release into a local repo.
# Both are in Fedora now, so that step only added an untrusted, unsigned repo.

have dnf || die "no dnf; sdata/dist-fedora is for Fedora and its derivatives"

if [[ -n "$OS_VERSION_ID" ]] && (( ${OS_VERSION_ID%%.*} < 43 )); then
    die "Fedora ${OS_VERSION_ID} is too old; the COPRs build for 43 and later"
fi

# The chroots each of these publishes for are fedora-43, fedora-44 and rawhide,
# x86_64 and aarch64.
FEDORA_COPRS=(
    # Hyprland stack. solopasha/hyprland is the better known one and is stale
    # (0.49 against sdegler's 0.56), so it is deliberately not used.
    sdegler/hyprland
    # The KOOMPI font set, bibata, breeze-plus, microtex, songrec.
    ririko66z/dots-hyprland
    # Darkly, the Qt style the desktop themes through.
    deltacopy/darkly
    # starship is the only one of these not in Fedora proper.
    atim/starship
)

step "Fedora: refreshing packages"
run sudo dnf upgrade --refresh -y

step "Fedora: enabling COPRs"
for _copr in "${FEDORA_COPRS[@]}"; do
    run sudo dnf copr enable -y "$_copr"
done
unset _copr

# quickshell links private Qt APIs, so it breaks the moment qt6-qtbase moves
# under it. The lock has to come off before an upgrade or dnf refuses to
# proceed; it goes back on at the end.
fedora_unlock_quickshell() {
    rpm -q python3-dnf-plugin-versionlock >/dev/null 2>&1 \
        || rpm -q dnf-plugin-versionlock >/dev/null 2>&1 \
        || run sudo dnf install -y 'dnf-command(versionlock)'
    sudo dnf versionlock delete quickshell >/dev/null 2>&1 || true
}
fedora_lock_quickshell() {
    if sudo dnf versionlock add quickshell >/dev/null 2>&1; then
        info "quickshell pinned; run 'sudo dnf versionlock delete quickshell' before upgrading Qt"
    fi
}

fedora_unlock_quickshell

step "Fedora: installing packages"
mapfile -t _fedora_pkgs < <(sed -e 's/#.*//' -e '/^[[:space:]]*$/d' -e 's/[[:space:]]*$//' \
    "$REPO_ROOT/sdata/dist-fedora/packages.list")
info "${#_fedora_pkgs[@]} packages"
# --skip-unavailable rather than a hard fail: a COPR rebuilding for a new Fedora
# release should cost the user one widget, not the whole install. The doctor
# command reports what actually landed.
run sudo dnf install -y --setopt=install_weak_deps=False --skip-unavailable "${_fedora_pkgs[@]}"
unset _fedora_pkgs

fedora_lock_quickshell

# Fedora needs no source builds, but the fonts only arrive if the COPR built
# them for this release. Fill any gap from upstream releases.
source "$REPO_ROOT/sdata/lib/from-source.sh"
install_fonts_from_release
install_google_sans_flex
install_nerd_font

if ! have quickshell && ! have qs; then
    warn "quickshell did not install."
    warn "Fedora ships 0.2.1; for 0.3.x run: sudo dnf copr enable errornointernet/quickshell -y"
    warn "then re-run ./setup install --only-deps"
fi
