# shellcheck shell=bash
# Sourced by sdata/install/apps.sh. Installs the opinionated KOOMPI agent
# workbench without taking ownership of system Node modules or user credentials.

readonly AGENT_NPM_PREFIX="${XDG_DATA_HOME}/koompi/npm"

# Symmetric with run_official_installer below: present means done. Both of these
# CLIs update themselves, so re-running `npm install --global` on every setup
# spends a network round trip and a package extraction to arrive back where it
# started. KOOMPI_AGENTS_REFRESH=1 forces the install for a deliberate repair.
install_npm_agent() {
    local command_name="$1"
    shift

    if have "$command_name" && [[ "${KOOMPI_AGENTS_REFRESH:-0}" != 1 ]]; then
        ok "$command_name already installed"
        return 0
    fi

    if ! have npm; then
        warn "npm is missing; cannot install ${command_name}"
        return 0
    fi

    run mkdir -p "$AGENT_NPM_PREFIX" "$XDG_BIN_HOME"
    run npm install --global --prefix "$AGENT_NPM_PREFIX" "$@"
    run ln -sfn "$AGENT_NPM_PREFIX/bin/$command_name" "$XDG_BIN_HOME/$command_name"
}

install_cli_compat() {
    # Debian-family packages expose these two tools under collision-avoiding
    # names. Keep KOOMPI's shell and documentation identical across distros.
    if ! have fd && have fdfind; then
        run ln -sfn "$(command -v fdfind)" "$XDG_BIN_HOME/fd"
    fi
    if ! have bat && have batcat; then
        run ln -sfn "$(command -v batcat)" "$XDG_BIN_HOME/bat"
    fi
}

run_official_installer() {
    local name="$1" command_name="$2" url="$3"
    if have "$command_name" && [[ "${KOOMPI_AGENTS_REFRESH:-0}" != 1 ]]; then
        ok "$name already installed"
        return 0
    fi

    local installer
    installer="$(mktemp)"
    run curl -fsSL --retry 3 --connect-timeout 15 -o "$installer" "$url"
    run bash "$installer"
    rm -f "$installer"

    export PATH="$XDG_BIN_HOME:$PATH"
    if [[ "$DRY_RUN" != true ]] && ! have "$command_name"; then
        warn "$name installer finished but '${command_name}' is not on PATH"
    fi
}

install_agent_tools() {
    step "KOOMPI Workbench"
    info "agent CLIs are user-local; authentication remains per-user and is never scripted"
    run mkdir -p "$XDG_BIN_HOME"
    export PATH="$XDG_BIN_HOME:$AGENT_NPM_PREFIX/bin:$PATH"
    install_cli_compat

    # Official npm packages. Pi explicitly recommends --ignore-scripts; Codex
    # does not, so keep the two install contracts separate.
    install_npm_agent codex @openai/codex
    install_npm_agent pi --ignore-scripts @earendil-works/pi-coding-agent

    # Official native installers. Claude's native channel auto-updates; Herdr
    # exposes its updater through `herdr update`.
    run_official_installer "Claude Code" claude "https://claude.ai/install.sh"
    run_official_installer "Herdr" herdr "https://herdr.dev/install.sh"

    if [[ "$DRY_RUN" != true ]]; then
        local cmd
        for cmd in claude codex pi herdr nvim; do
            if have "$cmd"; then ok "$cmd"; else warn "$cmd is missing"; fi
        done
    fi
}
