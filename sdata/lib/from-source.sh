# shellcheck shell=bash
# Sourced by ./setup. The things no apt or dnf repository provides.
#
# Used by the Fedora and Debian recipes. Arch needs none of this - everything
# here exists in the AUR and is covered by a PKGBUILD in sdata/dist-arch/.
#
# Every function is a no-op when the thing is already present, so a recipe can
# call all of them unconditionally and re-running ./setup costs nothing.

FONT_DIR="${XDG_DATA_HOME}/fonts/koompi"
LOCAL_BIN=/usr/local/bin

_fetch() {
    local url="$1" out="$2"
    run curl -fsSL --retry 3 --connect-timeout 15 -o "$out" "$url"
}

# The shell renders its icons as Material Symbols glyphs. Without that font
# every icon in the bar is a tofu box, so this is a hard requirement on any
# distro that does not package it - not a cosmetic extra.
install_fonts_from_release() {
    local -a fonts=(
        "Material Symbols Rounded|https://github.com/google/material-design-icons/raw/master/variablefont/MaterialSymbolsRounded%5BFILL%2CGRAD%2Copsz%2Cwght%5D.ttf|MaterialSymbolsRounded.ttf"
        "Readex Pro|https://github.com/ThomasJockin/readexpro/raw/master/fonts/variable/ReadexPro%5BHEXP%2Cwght%5D.ttf|ReadexPro.ttf"
        "Space Grotesk|https://github.com/floriankarsten/space-grotesk/raw/master/fonts/variable/SpaceGrotesk%5Bwght%5D.ttf|SpaceGrotesk.ttf"
        "Rubik|https://github.com/googlefonts/rubik/raw/main/fonts/variable/Rubik%5Bwght%5D.ttf|Rubik.ttf"
    )
    local entry name url file missing=()
    for entry in "${fonts[@]}"; do
        IFS='|' read -r name url file <<< "$entry"
        if fc-list 2>/dev/null | grep -qi "$name"; then continue; fi
        missing+=("$entry")
    done
    (( ${#missing[@]} )) || { info "fonts already present"; return 0; }

    step "Fonts (${#missing[@]} missing)"
    run mkdir -p "$FONT_DIR"
    for entry in "${missing[@]}"; do
        IFS='|' read -r name url file <<< "$entry"
        info "$name"
        _fetch "$url" "$FONT_DIR/$file"
    done
    run fc-cache -f "$FONT_DIR"
}

# Google Sans Flex is the UI typeface. It is a git repo of build outputs rather
# than a release artefact, so it is cloned.
install_google_sans_flex() {
    fc-list 2>/dev/null | grep -qi "Google Sans Flex" && return 0
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
    fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd" && return 0
    step "JetBrains Mono Nerd Font"
    local tmp
    tmp="$(mktemp -d)"
    _fetch "https://github.com/ryanoasis/nerd-fonts/releases/latest/download/JetBrainsMono.tar.xz" "$tmp/f.tar.xz"
    run mkdir -p "$FONT_DIR/JetBrainsMono"
    run tar -xf "$tmp/f.tar.xz" -C "$FONT_DIR/JetBrainsMono"
    rm -rf "$tmp"
    run fc-cache -f "$FONT_DIR"
}

# GTK apps read the theme by name from gsettings; without adw-gtk3 on disk the
# name resolves to nothing and they stay stock Adwaita.
install_adw_gtk3() {
    [[ -d /usr/share/themes/adw-gtk3 || -d "${XDG_DATA_HOME}/themes/adw-gtk3" ]] && return 0
    step "adw-gtk3 theme"
    local tmp
    tmp="$(mktemp -d)"
    _fetch "https://github.com/lassekongo83/adw-gtk3/releases/latest/download/adw-gtk3.tar.xz" "$tmp/t.tar.xz" \
        || { warn "could not fetch adw-gtk3; GTK apps will stay unthemed"; rm -rf "$tmp"; return 0; }
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
    _fetch "https://github.com/mikefarah/yq/releases/latest/download/yq_linux_${arch_suffix}" "$tmp/yq"
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
    _fetch "https://raw.githubusercontent.com/Gustash/hyprshot/main/hyprshot" "$tmp"
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

install_matugen() {
    have matugen && return 0
    step "matugen"
    local arch_suffix
    case "$OS_ARCH" in
        x86_64)  arch_suffix=x86_64-unknown-linux-gnu ;;
        aarch64) arch_suffix=aarch64-unknown-linux-gnu ;;
        *)       warn "no matugen build for $OS_ARCH; colour generation stays off"; return 0 ;;
    esac
    local tmp
    tmp="$(mktemp -d)"
    if ! _fetch "https://github.com/InioX/matugen/releases/latest/download/matugen-${arch_suffix}.tar.gz" "$tmp/m.tar.gz"; then
        warn "could not fetch matugen; koompi-theme will keep the current colours"
        rm -rf "$tmp"; return 0
    fi
    run tar -xf "$tmp/m.tar.gz" -C "$tmp"
    local bin
    bin="$(find "$tmp" -type f -name matugen -perm -u+x | head -1)"
    [[ -n "$bin" ]] && run sudo install -Dm755 "$bin" "$LOCAL_BIN/matugen"
    rm -rf "$tmp"
}
