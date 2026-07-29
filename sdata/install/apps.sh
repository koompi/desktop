# shellcheck shell=bash
# Sourced by ./setup. Routes to the application recipe for the detected distro.
#
# This is a separate step from deps.sh on purpose. The dependency step installs
# what the session cannot start without; this one installs the programs KOOMPI
# has an opinion about. Skipping it with --no-apps leaves you a working desktop
# with whatever applications you already had.

# Named for the confirmation prompt, so someone who has never read this repo
# still knows what is about to land on their disk.
readonly APPS_SUMMARY='KOOMPI Workbench (Claude Code, Codex, Pi, Herdr, Neovim),
  wezterm, konsole, zed, chrome, brave, dolphin extras, okular, loupe, mpv,
  libreoffice, btop, kdeconnect and a modern command-line toolkit'

install_apps() {
    step "Installing applications"

    if [[ -z "$OS_GROUP_ID" ]]; then
        die "no application recipe for this distro; re-run with --no-apps"
    fi

    local recipe="$REPO_ROOT/sdata/dist-${OS_GROUP_ID}/install-apps.sh"
    [[ -f "$recipe" ]] || die "missing recipe: $recipe"

    # Several gigabytes, two proprietary browsers, and an office suite. That is
    # the right default for a KOOMPI machine and the wrong thing to do silently
    # to someone who piped this in to try the shell out.
    #
    # Someone who already said yes once should not be asked again on every
    # update, so the question is only worth putting to a machine that does not
    # already have the set. The recipe still runs either way: it skips what is
    # present by itself, and that is what picks up applications added upstream
    # since the last run.
    local cmd missing=0
    for cmd in "${APP_CMDS[@]}" "${AGENT_CMDS[@]}"; do
        have "$cmd" || missing=$((missing + 1))
    done

    if (( missing == 0 )); then
        ok "the KOOMPI application set is already present; checking for additions"
    else
        printf '\n  The KOOMPI application set:\n  %s\n\n' "$APPS_SUMMARY"
        if ! confirm "Install these? (no = keep the applications you already have)"; then
            warn "skipped; the desktop works, but keybinds fall back to whatever is on PATH"
            return 0
        fi
    fi

    info "using $recipe"
    # shellcheck source=/dev/null
    source "$recipe"

    # Agent CLIs update too quickly for distro archives. They are installed
    # user-locally from their official distribution channels after the distro
    # recipe has supplied Node/npm and the native CLI foundation.
    # shellcheck source=sdata/install/agents.sh
    source "$REPO_ROOT/sdata/install/agents.sh"
    install_agent_tools

    ok "applications installed"
}
