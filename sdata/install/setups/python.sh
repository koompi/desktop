# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. The Python venv the colour pipeline and thumbnails run in.

# The shell's Python helpers run out of a venv rather than site-packages so an
# OS Python upgrade cannot break the desktop, and so the same requirements
# resolve identically on Arch, Fedora and Debian.
setup_python_venv() {
    step "Python environment"
    if ! have uv; then
        warn "uv not found; skipping the venv."
        warn "Wallpaper colour generation and thumbnails will not work until it exists."
        return 0
    fi
    run mkdir -p "$(dirname "$VENV_DIR")"
    # No --python pin: the venv must be built on the distro's own interpreter or
    # --system-site-packages cannot see the distro PyGObject and opencv, which
    # are taken from packages rather than built here.
    if [[ -x "$VENV_DIR/bin/python" ]]; then
        info "venv already exists; syncing requirements only"
    else
        run uv venv --system-site-packages "$VENV_DIR"
    fi
    run uv pip install --python "$VENV_DIR/bin/python" \
        -r "$REPO_ROOT/sdata/uv/requirements.txt"
    ok "venv ready at $VENV_DIR"
}
