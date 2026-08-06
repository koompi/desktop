# shellcheck shell=bash
# Sourced by ./setup. The things no apt or dnf repository provides, used by the
# Fedora and Debian recipes; Arch covers all of it through the AUR. Every function is
# a no-op when the thing is present, so a recipe can call them unconditionally.

FONT_DIR="${XDG_DATA_HOME}/fonts/koompi"
LOCAL_BIN=/usr/local/bin

# try(), not run(). Under --yes a failed run() calls die, so the whole install
# went down on one moved release asset and every `_fetch ... || warn` below it
# was unreachable.
_fetch() {
    try curl -fsSL --retry 3 --connect-timeout 15 -o "$2" "$1"
}

# The tag of a project's newest GitHub release, from the redirect that
# /releases/latest serves. Cheaper than the API and not rate limited, which
# matters for a step every install runs.
_github_latest_tag() {
    local url
    url="$(curl -fsSLI -o /dev/null -w '%{url_effective}' \
        "https://github.com/$1/releases/latest" 2>/dev/null)" || return 1
    [[ "$url" == */tag/* ]] || return 1
    printf '%s\n' "${url##*/tag/}"
}

# `fc-list | grep -q` is not this check. grep -q closes the pipe on its first
# match, ./setup runs under `set -o pipefail`, and fc-list's output is far larger
# than a pipe buffer, so fc-list dies of SIGPIPE and the pipeline reports 141 -
# every font reads as missing even when it is installed. That is what had Fedora
# re-downloading four fonts its own RPMs had just put on disk, and re-cloning
# Google Sans Flex and the 30 MiB Nerd Font tarball on every single run.
_font_installed() {
    local listed
    listed="$(fc-list 2>/dev/null)" || return 1
    grep -qi -- "$1" <<< "$listed"
}

# The shell renders its icons as Material Symbols glyphs. Without that font
# every icon in the bar is a tofu box, so this is a hard requirement on any
# distro that does not package it - not a cosmetic extra.
install_fonts_from_release() {
    local -a fonts=(
        "Material Symbols Rounded|https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf|MaterialSymbolsRounded.ttf"
        # Both designers' own repos dropped fonts/variable/ and the old paths
        # 404. google/fonts is where the released variable build lives now.
        "Readex Pro|https://github.com/google/fonts/raw/main/ofl/readexpro/ReadexPro%5BHEXP%2Cwght%5D.ttf|ReadexPro.ttf"
        "Space Grotesk|https://github.com/google/fonts/raw/main/ofl/spacegrotesk/SpaceGrotesk%5Bwght%5D.ttf|SpaceGrotesk.ttf"
        "Rubik|https://github.com/googlefonts/rubik/raw/main/fonts/variable/Rubik%5Bwght%5D.ttf|Rubik.ttf"
    )
    local entry name url file missing=()
    for entry in "${fonts[@]}"; do
        IFS='|' read -r name url file <<< "$entry"
        _font_installed "$name" && continue
        missing+=("$entry")
    done
    (( ${#missing[@]} )) || { info "fonts already present"; return 0; }

    step "Fonts (${#missing[@]} missing)"
    run mkdir -p "$FONT_DIR"
    for entry in "${missing[@]}"; do
        IFS='|' read -r name url file <<< "$entry"
        info "$name"
        _fetch "$url" "$FONT_DIR/$file" && continue
        rm -f "$FONT_DIR/$file"
        # Material Symbols is what every icon in the shell is drawn from, so a
        # bar of tofu boxes is not a partial install worth finishing quietly.
        [[ "$name" == "Material Symbols Rounded" ]] \
            && die "could not fetch $name; without it every icon in the shell is a blank box"
        warn "could not fetch $name; text using it falls back to another face"
    done
    run fc-cache -f "$FONT_DIR"
}

# Google Sans Flex is the UI typeface. It is a git repo of build outputs rather
# than a release artefact, so it is cloned.
install_google_sans_flex() {
    _font_installed "Google Sans Flex" && return 0
    step "Google Sans Flex"
    local dir="$FONT_DIR/google-sans-flex"
    if [[ -d "$dir/.git" ]]; then
        run git -C "$dir" pull --ff-only
    else
        run git clone --depth 1 https://github.com/end-4/google-sans-flex "$dir"
    fi
    run fc-cache -f "$FONT_DIR"
}

# JetBrains Mono is widely packaged, but only the unpatched upstream; the shell
# wants the Nerd Font build for its glyph range.
install_nerd_font() {
    _font_installed "JetBrainsMono Nerd" && return 0
    step "JetBrains Mono Nerd Font"
    local tmp
    tmp="$(mktemp -d)"
    _fetch "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" "$tmp/f.tar.xz" \
        || { warn "could not fetch JetBrains Mono Nerd Font; the bar and the terminal lose their glyphs"; rm -rf "$tmp"; return 0; }
    run mkdir -p "$FONT_DIR/JetBrainsMono"
    run tar -xf "$tmp/f.tar.xz" -C "$FONT_DIR/JetBrainsMono"
    rm -rf "$tmp"
    run fc-cache -f "$FONT_DIR"
}

# GTK apps read the theme by name from gsettings; without adw-gtk3 on disk the
# name resolves to nothing and they stay stock Adwaita.
# The asset is named adw-gtk3v6.5.tar.xz, version and all, so the tag has to be
# resolved before it can be addressed.
install_adw_gtk3() {
    [[ -d /usr/share/themes/adw-gtk3 || -d "${XDG_DATA_HOME}/themes/adw-gtk3" ]] && return 0
    step "adw-gtk3 theme"
    local tag
    if ! tag="$(_github_latest_tag lassekongo83/adw-gtk3)"; then
        warn "could not reach the adw-gtk3 releases; GTK apps will stay unthemed"
        return 0
    fi
    local tmp
    tmp="$(mktemp -d)"
    _fetch "https://github.com/lassekongo83/adw-gtk3/releases/download/${tag}/adw-gtk3${tag}.tar.xz" "$tmp/t.tar.xz" \
        || { warn "could not fetch adw-gtk3 ${tag}; GTK apps will stay unthemed"; rm -rf "$tmp"; return 0; }
    run mkdir -p "${XDG_DATA_HOME}/themes"
    run tar -xf "$tmp/t.tar.xz" -C "${XDG_DATA_HOME}/themes"
    rm -rf "$tmp"
}

install_bibata_cursor() {
    [[ -d /usr/share/icons/Bibata-Modern-Classic || -d "${XDG_DATA_HOME}/icons/Bibata-Modern-Classic" ]] && return 0
    step "Bibata cursor theme"
    local tmp
    tmp="$(mktemp -d)"
    _fetch "https://github.com/ful1e5/Bibata_Cursor/releases/latest/download/Bibata-Modern-Classic.tar.xz" "$tmp/c.tar.xz" \
        || { warn "could not fetch Bibata; the stock cursor theme stays"; rm -rf "$tmp"; return 0; }
    run mkdir -p "${XDG_DATA_HOME}/icons"
    run tar -xf "$tmp/c.tar.xz" -C "${XDG_DATA_HOME}/icons"
    rm -rf "$tmp"
}

# uv is not in any Debian or Ubuntu release, and the Python venv step needs it.
install_uv() {
    have uv && return 0
    step "uv"
    info "installing from astral.sh (not packaged on this distro)"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s     $ curl -LsSf https://astral.sh/uv/install.sh | sh%s\n' "${C_DIM}" "${C_RST}"
        return 0
    fi
    curl -LsSf https://astral.sh/uv/install.sh | sh || die "uv install failed"
    have uv || export PATH="$HOME/.local/bin:$PATH"
}

# Debian's `yq` is a Python wrapper around jq with different syntax; the shell
# scripts use mikefarah's Go implementation and its `-o=j` flag.
install_go_yq() {
    if have yq && yq --version 2>&1 | grep -qi 'mikefarah\|^yq (https'; then return 0; fi
    step "yq (mikefarah/yq)"
    local arch_suffix
    case "$OS_ARCH" in
        x86_64)  arch_suffix=amd64 ;;
        aarch64) arch_suffix=arm64 ;;
        *)       warn "no yq build for $OS_ARCH; skipping"; return 0 ;;
    esac
    local tmp
    tmp="$(mktemp -d)"
    _fetch "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch_suffix}" "$tmp/yq" \
        || { warn "could not fetch yq; the scripts that read YAML config will fail"; rm -rf "$tmp"; return 0; }
    run chmod +x "$tmp/yq"
    run sudo install -Dm755 "$tmp/yq" "$LOCAL_BIN/yq"
    rm -rf "$tmp"
}

# A single bash script upstream, not packaged outside Arch and the Fedora COPRs.
install_hyprshot() {
    have hyprshot && return 0
    step "hyprshot"
    local tmp
    tmp="$(mktemp)"
    _fetch "https://raw.githubusercontent.com/Gustash/hyprshot/main/hyprshot" "$tmp" \
        || { warn "could not fetch hyprshot; the screenshot keybinds will do nothing"; rm -f "$tmp"; return 0; }
    run sudo install -Dm755 "$tmp" "$LOCAL_BIN/hyprshot"
    rm -f "$tmp"
}

# Zed is in Arch's extra but in no Fedora or Debian archive, and its own
# installer is the route upstream supports. It lands in ~/.local, so this is the
# one thing here that needs no sudo - and the one thing that is per-user, which
# is why it is not in packages-apps.list where it would look system-wide.
install_zed() {
    have zeditor && return 0
    [[ -x "$HOME/.local/bin/zeditor" ]] && return 0
    step "Zed"
    info "installing from zed.dev (not packaged on this distro)"
    if [[ "$DRY_RUN" == true ]]; then
        printf '%s     $ curl -f https://zed.dev/install.sh | sh%s\n' "${C_DIM}" "${C_RST}"
        return 0
    fi
    # Not fatal: variables.lua falls through to the next editor on the list.
    if ! curl -fsSL https://zed.dev/install.sh | sh; then
        warn "Zed install failed; the editor keybind will fall back to kate or a terminal editor"
    fi
}

# Neither apt nor dnf reliably offers a zig new enough: Debian 13 packages none,
# Ubuntu's `zig` metapackage pulls 0.14, and the global-menu daemon floors at
# ZIG_MIN. Without it the top bar's global menu stays empty and the koompi
# command never gets built, so this is a feature, not a toolchain nicety.
# zig is not a lone binary - it reads its own lib/ at runtime - so the whole
# tree is installed and only the entry point is linked onto PATH.
install_zig() {
    zig_usable && return 0
    step "zig ${ZIG_MIN}"
    local target
    case "$OS_ARCH" in
        x86_64)  target=x86_64-linux ;;
        aarch64) target=aarch64-linux ;;
        *)       warn "no zig build for $OS_ARCH; the global menu and the koompi command stay unbuilt"; return 0 ;;
    esac
    have zig && info "the packaged zig ($(zig version 2>/dev/null)) is below ${ZIG_MIN}; installing beside it"

    local tmp dir="/usr/local/lib/zig-${ZIG_MIN}"
    tmp="$(mktemp -d)"
    if ! _fetch "https://ziglang.org/download/${ZIG_MIN}/zig-${target}-${ZIG_MIN}.tar.xz" "$tmp/zig.tar.xz"; then
        warn "could not fetch zig; the global menu and the koompi command stay unbuilt"
        rm -rf "$tmp"; return 0
    fi
    run sudo mkdir -p "$dir"
    # --strip-components drops the versioned top directory so the layout is
    # stable whatever the tarball calls itself.
    run sudo tar -xf "$tmp/zig.tar.xz" -C "$dir" --strip-components=1
    run sudo ln -sfn "$dir/zig" "$LOCAL_BIN/zig"
    rm -rf "$tmp"
}

# The asset name carries the version, so /releases/latest/download/<name> cannot
# address it and the tag has to be resolved first. Upstream has published x86_64
# alone for every release back to 2.4.1; there is no aarch64 build to fetch.
install_matugen() {
    have matugen && return 0
    step "matugen"
    if [[ "$OS_ARCH" != x86_64 ]]; then
        warn "matugen publishes x86_64 builds only; on $OS_ARCH colour generation stays off"
        warn "build it from source (cargo install matugen) if you want wallpaper colours"
        return 0
    fi
    local tag ver
    if ! tag="$(_github_latest_tag InioX/matugen)"; then
        warn "could not reach the matugen releases; koompi-theme will keep the current colours"
        return 0
    fi
    ver="${tag#v}"
    local tmp
    tmp="$(mktemp -d)"
    if ! _fetch "https://github.com/InioX/matugen/releases/download/${tag}/matugen-${ver}-x86_64.tar.gz" "$tmp/m.tar.gz"; then
        warn "could not fetch matugen ${ver}; koompi-theme will keep the current colours"
        rm -rf "$tmp"; return 0
    fi
    run tar -xf "$tmp/m.tar.gz" -C "$tmp"
    local bin
    bin="$(find "$tmp" -type f -name matugen -perm -u+x | head -1)"
    [[ -n "$bin" ]] && run sudo install -Dm755 "$bin" "$LOCAL_BIN/matugen"
    rm -rf "$tmp"
}
