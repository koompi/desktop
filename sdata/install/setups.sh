# shellcheck shell=bash
# Sourced by ./setup. Everything that is neither "install a package" nor "copy a
# file": the Python venv the colour pipeline runs in, the compiled global-menu
# daemon, group membership, kernel modules and user services.

# systemctl on PATH is not a running manager. A container, a chroot and an image
# build all have the binary and no pid 1 to talk to, and every enable below then
# fails: /run/systemd/system is what sd_booted(3) itself looks for. The user
# manager is a second question, absent in any session logind did not create.
systemd_running() { [[ -d /run/systemd/system ]]; }
systemd_user_running() { systemctl --user show --property=Version >/dev/null 2>&1; }

# The native `koompi` command is the front door to desktop maintenance and the
# shipped helpers. Build it from the same checkout being installed so its
# command surface always matches the scripts and desktop version beside it.
setup_koompi_cli() {
    step "KOOMPI command line"
    local src="$REPO_ROOT/cli"
    local build_root="$XDG_CACHE_HOME/koompi/build/cli"
    local binary="$build_root/out/bin/koompi"
    [[ -f "$src/build.zig" ]] || { warn "CLI source not found, skipping"; return 0; }
    if ! zig_usable; then
        warn "zig ${ZIG_MIN} or newer not found; the koompi command cannot be built."
        warn "Install one, then re-run: ./setup install --only-setups"
        return 0
    fi
    run mkdir -p "$build_root"
    # Keep generated objects and the install prefix out of the checkout. A
    # user's KOOMPI source tree should stay clean after every install/update.
    run_in_dir "$src" zig build \
        --cache-dir "$build_root/cache" \
        --global-cache-dir "$XDG_CACHE_HOME/zig" \
        --prefix "$build_root/out" \
        -Doptimize=ReleaseSafe
    run install -Dm755 "$binary" "$XDG_BIN_HOME/koompi"
    manifest_add "$XDG_BIN_HOME/koompi"
    ok "koompi CLI installed"
}

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

# The global menu daemon is Zig source in the shell tree; zig-out/ is
# gitignored, so a fresh clone has no binary and the menu silently stays empty.
setup_global_menu() {
    step "Global menu daemon"
    # The shell resolves the binary at ../scripts/global-menu/zig-out/bin from
    # its own QML, so it has to be built where the config was installed, not in
    # the checkout. ./setup calls this after the files step for that reason.
    local src="${XDG_CONFIG_HOME}/quickshell/koompi/scripts/global-menu"
    [[ -d "$src" ]] || {
        warn "the shell config is not installed, so there is nowhere to build the daemon"
        warn "run './setup install --only-files' first, then './setup install --only-setups'"
        return 0
    }
    if ! zig_usable; then
        warn "zig ${ZIG_MIN} or newer not found; the global menu will be empty until it is built."
        warn "Install one, then re-run: ./setup install --only-setups"
        return 0
    fi
    # prefix stays zig-out/ in $src (the QML resolves it there); only the cache moves out
    run_in_dir "$src" zig build \
        --cache-dir "$XDG_CACHE_HOME/koompi/build/global-menu/cache" \
        --global-cache-dir "$XDG_CACHE_HOME/zig" \
        -Doptimize=ReleaseSafe
    ok "global-menu-daemon built"
}

# The Rust daemon answers the same stdio protocol as the zig one above, and the
# shell prefers it when it is present. Both are kept while the port is proven:
# tests/test_globalmenu.sh runs the one conformance suite against each. Unlike
# the zig build this installs to a normal bin dir, because nothing resolves it
# by a path relative to the QML.
setup_globalmenu_rs() {
    step "Global menu daemon (rust)"
    local src="$REPO_ROOT/globalmenu"
    local build_root="$XDG_CACHE_HOME/koompi/build/globalmenu"
    local binary="$build_root/release/global-menu-daemon"
    [[ -f "$src/Cargo.toml" ]] || { warn "globalmenu source not found, skipping"; return 0; }
    if ! cargo_usable; then
        warn "cargo ${RUST_MIN} or newer not found; the shell falls back to the zig daemon."
        warn "Install one, then re-run: ./setup install --only-setups"
        return 0
    fi
    # Same discipline as the zig builds: nothing generated lands in the checkout.
    ( cd "$src" && run cargo build --release --locked --target-dir "$build_root" )
    run install -Dm755 "$binary" "$XDG_BIN_HOME/koompi-global-menu-daemon"
    manifest_add "$XDG_BIN_HOME/koompi-global-menu-daemon"
    ok "koompi-global-menu-daemon installed"
}

# The shell's system integration: NetworkManager, UPower and the rest, read over
# D-Bus and published as NDJSON on stdio. Unlike the global menu there is no second
# implementation to fall back to, so a machine that cannot build this loses the
# features outright rather than falling back to a slower path. The warning says so.
setup_shell_services() {
    step "Shell services daemon"
    local src="$REPO_ROOT/shell-services"
    local build_root="$XDG_CACHE_HOME/koompi/build/shell-services"
    local binary="$build_root/release/koompi-shelld"
    [[ -f "$src/Cargo.toml" ]] || { warn "shell-services source not found, skipping"; return 0; }
    if ! cargo_usable; then
        warn "cargo ${RUST_MIN} or newer not found; the wifi list and the battery charge"
        warn "limit will be empty, because nothing else reads them. Install one, then"
        warn "re-run: ./setup install --only-setups"
        return 0
    fi
    ( cd "$src" && run cargo build --release --locked -p koompi-shelld --target-dir "$build_root" )
    run install -Dm755 "$binary" "$XDG_BIN_HOME/koompi-shelld"
    manifest_add "$XDG_BIN_HOME/koompi-shelld"
    ok "koompi-shelld installed"
}

# ddcutil needs i2c to talk to external monitors; ydotool and the on-screen
# keyboard need uinput. Both are group + module questions, not package ones.
setup_groups_and_modules() {
    step "Groups, kernel modules and udev"
    local groups=(video input)
    if getent group i2c >/dev/null 2>&1; then
        groups+=(i2c)
    elif [[ "$OS_GROUP_ID" != fedora ]]; then
        run sudo groupadd i2c
        groups+=(i2c)
    fi
    run sudo usermod -aG "$(IFS=,; echo "${groups[*]}")" "$(id -un)"
    info "group changes take effect at your next login"

    sudo_write /etc/modules-load.d/koompi.conf $'i2c-dev\nuinput'
    sudo_write /etc/udev/rules.d/99-koompi-uinput.rules \
        'SUBSYSTEM=="misc", KERNEL=="uinput", MODE="0660", GROUP="input"'
    # The rule is on disk and applies from the next boot either way, and where
    # udevd is not running - a container, a chroot, an image build - there is
    # nothing to reload. Losing the file and service steps over that head start
    # is the wrong trade.
    try sudo udevadm control --reload-rules \
        || warn "could not reload udev rules; the uinput rule applies from your next boot"
}

# A wedged btintel_pcie returns -EBUSY from suspend forever, so the kernel aborts
# every suspend and logind retries every 30s until the battery is flat. Drop the
# module before sleep, reload after.
setup_suspend_hook() {
    step "Suspend reliability"
    systemd_running || { info "no running systemd; skipping"; return 0; }

    local hook=/usr/lib/systemd/system-sleep/koompi-btintel-pcie
    sudo_write "$hook" '#!/bin/sh
# Installed by KOOMPI. See setup_suspend_hook in sdata/install/setups.sh.
STAMP=/run/koompi-btintel-pcie-off
case "$1" in
pre)
    [ -d /sys/module/btintel_pcie ] || exit 0
    if modprobe -r btintel_pcie 2>/dev/null; then
        : > "$STAMP"
    else
        echo "koompi: btintel_pcie is busy and would not unload; suspend may fail" >&2
    fi
    ;;
post)
    [ -e "$STAMP" ] || exit 0
    rm -f "$STAMP"
    modprobe btintel_pcie
    ;;
esac
exit 0'
    run sudo chmod 755 "$hook"
}

# Swap on zram, systemd-oomd allowed to kill only user app scopes, and a 5 s
# stop timeout: what keeps a 4 GB machine's session alive under pressure. The
# ISO gets them from the koompi-sysdefaults package; this installs the same
# files under /usr/local/lib, which systemd and zram-generator read with the
# same precedence as /usr/lib and which pacman never owns, so installing the
# package later cannot collide. The reasons live in the files themselves.
setup_low_ram_defaults() {
    step "Low-RAM defaults (zram, oomd, fast shutdown)"
    systemd_running || { info "no running systemd; skipping"; return 0; }

    # Collected first: run() prompts on stdin when a command fails, and inside
    # a `find | while read` loop that prompt would eat the file list.
    local src="$REPO_ROOT/sdata/dist-arch/koompi-sysdefaults/files" file files=()
    mapfile -d '' files < <(find "$src" -type f -print0)
    (( ${#files[@]} )) || die "no files under $src"
    for file in "${files[@]}"; do
        run sudo install -Dm644 "$file" "/usr/local/lib/${file#"$src/"}"
    done

    # The package declares zram-generator as a dependency; from git it has to
    # be asked for by name. Without it the zram drop-in is inert.
    if [[ ! -x /usr/lib/systemd/system-generators/zram-generator ]]; then
        case "$OS_GROUP_ID" in
            arch)   run sudo pacman -S --needed --noconfirm zram-generator ;;
            fedora) run sudo dnf install -y zram-generator ;;
            debian) run sudo apt-get install -y systemd-zram-generator ;;
            *)      warn "zram-generator is not installed; no zram swap until it is" ;;
        esac
    fi

    # daemon-reload re-runs the generators and re-reads system.conf.d, so the
    # zram unit and the 5 s default exist now. The swap device itself is only
    # started where no zram swap exists yet: resizing a live one means swapoff
    # first, which on a loaded machine is the one thing this step must not do.
    run sudo systemctl daemon-reload
    if ! grep -q '^/dev/zram' /proc/swaps; then
        try sudo systemctl start systemd-zram-setup@zram0.service \
            || warn "could not start zram swap now; it starts at the next boot"
    fi

    # oomd reads its thresholds at startup only: restart, not just enable, or a
    # daemon that was already running keeps the stock 60% / 30 s until reboot.
    # It needs cgroup v2 with PSI; where it cannot run, say so and carry on.
    if try sudo systemctl enable systemd-oomd.service \
        && try sudo systemctl restart systemd-oomd.service; then
        ok "systemd-oomd running with the KOOMPI thresholds"
    else
        warn "could not start systemd-oomd; memory pressure can still take the session down"
    fi
    # app.slice candidacy is reported by the user manager; reload it so oomd
    # sees it now rather than at the next login.
    if systemd_user_running; then
        run systemctl --user daemon-reload
    else
        warn "no user systemd manager here; oomd sees app.slice from your next login"
    fi
}

# ydotool ships a system unit on most distros but the shell drives it as a user
# service; link it into the user manager where the distro has not.
setup_services() {
    step "User services"
    systemd_running || { warn "no running systemd; start ydotool yourself"; return 0; }

    if [[ ! -e /usr/lib/systemd/user/ydotool.service ]] \
       && [[ -e /usr/lib/systemd/system/ydotool.service ]]; then
        run sudo ln -sf /usr/lib/systemd/system/ydotool.service \
                        /usr/lib/systemd/user/ydotool.service
    fi
    if [[ ! -e /usr/lib/systemd/user/ydotool.service ]]; then
        warn "no ydotool user service found; input synthesis will not work"
    elif ! systemd_user_running; then
        warn "no user systemd manager here; enable ydotool after your next login"
    else
        run systemctl --user enable --now ydotool
    fi
    if systemctl list-unit-files bluetooth.service >/dev/null 2>&1; then
        run sudo systemctl enable --now bluetooth
    fi

    # Only useful with a touchscreen, and it needs python-evdev to start at all.
    # Enabled without --now: the unit is WantedBy=graphical-session.target and
    # starts with the next session.
    if ! python3 -c 'import evdev' 2>/dev/null; then
        warn "python-evdev missing; touchscreen drag-to-scroll not enabled"
    elif ! systemd_user_running; then
        warn "no user systemd manager here; enable touch-gestures after your next login"
    else
        run systemctl --user enable touch-gestures
    fi

    # The idle daemon (idle lock, dpms, suspend; relays logind Lock to the
    # shell). The packaged unit is WantedBy=graphical-session.target, which
    # execs.lua starts once WAYLAND_DISPLAY is in the manager environment, so
    # it logs to the journal and restarts on crash. Enabled without --now: a
    # session that still runs the old exec-started hypridle would get two.
    if [[ ! -e /usr/lib/systemd/user/hypridle.service ]]; then
        warn "hypridle is not installed; the session will not lock on idle or lid close"
    elif ! systemd_user_running; then
        warn "no user systemd manager here; enable hypridle after your next login"
    else
        run systemctl --user enable hypridle
    fi

    # Notifies at login if a per-user migration is pending. Enabled without
    # --now, same as touch-gestures: the unit is WantedBy=graphical-session.target
    # and starts with the next session.
    if ! systemd_user_running; then
        warn "no user systemd manager here; enable koompi-migrate-notify after your next login"
    else
        run systemctl --user enable koompi-migrate-notify
    fi

    # No-ops unless koompi-snapshot-boot-check.service (system unit, btrfs
    # installs only) flagged a booted snapshot - safe to enable unconditionally.
    if ! systemd_user_running; then
        warn "no user systemd manager here; enable koompi-snapshot-notify after your next login"
    else
        run systemctl --user enable koompi-snapshot-notify
    fi
}

# The sidebar's local model runs on LiteRT-LM, which serves an OpenAI-compatible
# API on 127.0.0.1:9379. The CLI and the config land on every install; the 2.6 GB
# of weights are asked for, because a desktop install has no business pulling
# that down uninvited.
readonly LOCAL_AI_MODEL_ID=gemma4-e2b
readonly LOCAL_AI_MODEL_REPO=litert-community/gemma-4-E2B-it-litert-lm
readonly LOCAL_AI_MODEL_FILE=gemma-4-E2B-it.litertlm

setup_local_ai() {
    step "Local AI"
    if ! have uv; then
        warn "uv not found; the sidebar's local model will have nothing to talk to"
        return 0
    fi

    export PATH="$XDG_BIN_HOME:$PATH"
    if have litert-lm; then
        # serve(1) only exists from v0.13. An older pin looks like a missing feature.
        run uv tool upgrade litert-lm
    else
        run uv tool install litert-lm
    fi
    write_litert_lm_config

    if [[ "$DRY_RUN" != true ]] && ! litert-lm list 2>/dev/null | grep -q "$LOCAL_AI_MODEL_ID"; then
        printf '\n  The sidebar answers offline once a model is on disk.\n'
        printf '  %s is a 2.6 GB download.\n\n' "$LOCAL_AI_MODEL_ID"
        if confirm "Download it now? (no = the sidebar stays on its remote model)"; then
            run litert-lm import --from-huggingface-repo "$LOCAL_AI_MODEL_REPO" \
                "$LOCAL_AI_MODEL_FILE" "$LOCAL_AI_MODEL_ID"
        else
            info "skipped; run 'litert-lm import --from-huggingface-repo $LOCAL_AI_MODEL_REPO $LOCAL_AI_MODEL_FILE $LOCAL_AI_MODEL_ID' when you want it"
            return 0
        fi
    fi

    if ! systemd_user_running; then
        warn "no user systemd manager here; enable litert-lm.socket after your next login"
    else
        # the socket only: litert-lm and its watchdog are pulled in on the first
        # request and released again once the sidebar has been shut for 5min
        run systemctl --user enable litert-lm.socket
        # an install from before the socket wanted these off
        # graphical-session.target, which pins the engine for the whole session
        # and leaves StopWhenUnneeded nothing to act on
        run systemctl --user disable litert-lm.service litert-lm-watchdog.service
    fi

    setup_local_search
}

# The assistant's long-term memory. services/MemoryService.qml execs
# ~/.local/bin/koompi-agent-memd and, until this existed, nothing on a fresh
# machine ever put a binary there: the assistant forgot the owner's name, their
# preferences and their projects at every logout and said nothing about why.
#
# Its own repository, so the source is a sibling checkout where there is one and
# a clone into the build cache otherwise. Same shape as setup_shell_services
# below it: build, install to a bin dir, and name what is lost when the toolchain
# is not there.
readonly MEMD_REPO_URL="https://github.com/rithythul/koompi-agent-memd.git"

# Answers in MEMD_SRC rather than on stdout: run() and try() echo the command
# they are about to run, and a command substitution would capture that echo as
# part of the path.
MEMD_SRC=''
memd_source() {
    local sibling cached
    MEMD_SRC=''
    sibling="$(dirname -- "$REPO_ROOT")/koompi-agent-memd"
    if [[ -f "$sibling/Cargo.toml" ]]; then
        MEMD_SRC="$sibling"
        return 0
    fi

    cached="$XDG_CACHE_HOME/koompi/src/koompi-agent-memd"
    if [[ -f "$cached/Cargo.toml" ]]; then
        try git -C "$cached" pull --ff-only \
            || warn "could not update $cached; building the checkout that is already there"
        MEMD_SRC="$cached"
        return 0
    fi

    have git || { warn "git not found, and no koompi-agent-memd checkout beside this one"; return 1; }
    mkdir -p "$(dirname -- "$cached")"
    try git clone --depth 1 "$MEMD_REPO_URL" "$cached" || return 1
    MEMD_SRC="$cached"
    [[ "$DRY_RUN" == true ]] && return 0
    [[ -f "$cached/Cargo.toml" ]] || { warn "the clone left no Cargo.toml at $cached"; return 1; }
}

setup_agent_memory() {
    step "Assistant memory"
    local build_root binary
    build_root="$XDG_CACHE_HOME/koompi/build/koompi-agent-memd"
    binary="$build_root/release/koompi-agent-memd"

    if ! cargo_usable; then
        warn "cargo ${RUST_MIN} or newer not found, so the memory daemon cannot be built."
        warn "The assistant still answers, but it forgets your name, your preferences and"
        warn "what you are working on at every logout, and nothing on screen says so."
        warn "Install a Rust toolchain, then re-run: ./setup install --only-setups"
        return 0
    fi

    if ! memd_source; then
        warn "no koompi-agent-memd source; the assistant will have no long-term memory."
        warn "Clone $MEMD_REPO_URL beside this checkout, then re-run: ./setup install --only-setups"
        return 0
    fi
    info "building from $MEMD_SRC"

    run_in_dir "$MEMD_SRC" cargo build --release --locked --target-dir "$build_root"
    if [[ "$DRY_RUN" != true && ! -x "$binary" ]]; then
        warn "koompi-agent-memd did not build; the assistant will have no long-term memory"
        return 0
    fi
    run install -Dm755 "$binary" "$XDG_BIN_HOME/koompi-agent-memd"
    manifest_add "$XDG_BIN_HOME/koompi-agent-memd"
    verify_agent_memory "$XDG_BIN_HOME/koompi-agent-memd"
}

# The daemon has no --version: it speaks NDJSON on stdio and announces itself with
# an id:0 ready banner once the embedding model is loaded. Asking it for that
# banner is the only check that proves the thing the shell will do actually works,
# so it is worth the one cold start.
verify_agent_memory() {
    local bin="$1" db_dir banner
    [[ "$DRY_RUN" == true ]] && { info "would run $bin once to check it answers"; return 0; }

    # a private dir, not a predicted name: sqlite also leaves -wal/-shm siblings
    db_dir="$(mktemp -d "${TMPDIR:-/tmp}/koompi-memd-check.XXXXXX")" || { warn "cannot create a scratch directory to check koompi-agent-memd"; return 0; }
    info "starting it once to see that it answers; a first run also fetches the embedding model (~100 MB)"
    banner="$(KOOMPI_AGENT_MEMORY_DB="$db_dir/memory.db" KOOMPI_AGENT_T0_QUIET_SECS=0 KOOMPI_AGENT_T1_IDLE_SECS=0 \
        timeout 600 "$bin" < /dev/null 2>/dev/null | head -n 1)"
    rm -rf -- "${db_dir:?}"

    case "$banner" in
        *'"ok":true'*) ok "koompi-agent-memd ready: $banner" ;;
        "")            warn "koompi-agent-memd is installed but printed no ready banner; the assistant will have no memory."
                       warn "Run it by hand to see why: $bin < /dev/null" ;;
        *)             warn "koompi-agent-memd answered, but not with a ready banner: $banner" ;;
    esac
}

# The sidebar's search_web tool. Every free engine blocks a scraper, so the
# lookup goes through a SearXNG of our own on loopback: no API key, and the
# queries do not leave the machine to a third party.
readonly SEARXNG_PORT=8888

setup_local_search() {
    local runtime=""
    have docker && runtime=docker
    [[ -z "$runtime" ]] && have podman && runtime=podman
    if [[ -z "$runtime" ]]; then
        warn "no docker or podman; the sidebar can still read URLs but search_web will be dead"
        return 0
    fi

    local conf="$XDG_CONFIG_HOME/searxng"
    if [[ ! -f "$conf/settings.yml" ]]; then
        run mkdir -p "$conf"
        if [[ "$DRY_RUN" != true ]]; then
            # json is not in the default formats list, and the tool speaks only json
            cat > "$conf/settings.yml" <<EOF
use_default_settings: true

general:
  instance_name: "KOOMPI local search"
  donation_url: false
  contact_url: false

server:
  secret_key: "$(head -c 32 /dev/urandom | base64 | tr -d '\n/+=' | head -c 32)"
  limiter: false
  public_instance: false
  image_proxy: false
  method: "GET"

search:
  safe_search: 0
  autocomplete: ""
  default_lang: "all"
  formats:
    - html
    - json

ui:
  static_use_hash: true
EOF
        fi
    fi

    if [[ "$DRY_RUN" != true ]] && "$runtime" inspect searxng >/dev/null 2>&1; then
        info "searxng container already present"
        return 0
    fi
    run "$runtime" run -d --name searxng --restart unless-stopped \
        -p "127.0.0.1:$SEARXNG_PORT:8080" \
        -v "$conf:/etc/searxng" \
        -e "SEARXNG_BASE_URL=http://127.0.0.1:$SEARXNG_PORT/" \
        docker.io/searxng/searxng:latest
}

# Written rather than shipped through dots/ because ~/.litert-lm is the CLI's own
# directory and holds the imported models beside it.
#
# The key is `default`. `global_defaults` reads like the right name, and the
# schema sets additionalProperties:true, so a wrong top-level key is accepted in
# silence and nothing under it ever applies. The server logs "Using <field> from
# config" at engine init; that line is the only proof it landed.
#
# max_num_tokens has to clear the 4096 default: one get_shell_config turn is
# already 6155 tokens and fails the whole request as too long.
write_litert_lm_config() {
    local config="$HOME/.litert-lm/config.json"
    [[ -e "$config" ]] && { info "$config exists; leaving it alone"; return 0; }
    [[ "$DRY_RUN" == true ]] && { info "would write $config"; return 0; }

    mkdir -p "$(dirname "$config")"
    cat > "$config" <<'EOF'
{
  "default": {
    "backend": "gpu",
    "cpu_thread_count": 8,
    "cache": "disk",
    "max_num_tokens": 16384
  }
}
EOF
    manifest_add "$config"
    ok "wrote $config"
}

# XDG_DESKTOP_PORTAL_DIR does not add a directory, it REPLACES every other one, so
# the old five-file whitelist made every backend outside it invisible.
# xdg-desktop-portal has searched
# ~/.local/share/xdg-desktop-portal/portals since 1.19, so koompi.portal ships there
# through dots/ and the override has nothing left to do.
setup_portals() {
    step "Desktop portals"
    systemd_running || { warn "no running systemd; skipping portal cleanup"; return 0; }

    local dropin="${XDG_CONFIG_HOME}/systemd/user/xdg-desktop-portal.service.d/koompi-remotedesktop.conf"
    if [[ -f "$dropin" ]] && grep -q 'XDG_DESKTOP_PORTAL_DIR' "$dropin"; then
        info "removing the portal directory override; it hid every backend it did not list"
        run rm -f "$dropin"
        run rmdir --ignore-fail-on-non-empty "$(dirname "$dropin")"
        warn "the old whitelist at ${XDG_DATA_HOME}/koompi/portals is now unused; left in place rather than deleted"
    fi

    systemd_user_running && run systemctl --user daemon-reload
    return 0
}

# The cursor theme KOOMPI ships. It has to be stated in four places that cannot
# read each other: hyprland/env.lua (XCURSOR_THEME), hyprland/execs.lua (hyprctl
# setcursor), gsettings for GTK, and the default-cursors fallback below. Change
# it here and in the two lua files; tests/test_cursor_theme.sh fails if they drift.
readonly KOOMPI_CURSOR_THEME='Adwaita'
readonly KOOMPI_CURSOR_SIZE=24

# The cursor of last resort, and it is reached far more often than "clients that
# set no theme". libXcursor resolves each requested name through the theme's
# Inherits chain and then through the `default` theme, so a name the session
# theme happens not to carry lands on whatever `default` points at. Adwaita ships
# 63 names and drops the legacy aliases; Qt/xcb clients ask for `pointing_hand`
# first, which Adwaita lacks. With `default` inheriting a second theme, that one
# request resolves there and Qt never falls through to the `hand2` Adwaita does
# have - so a single shape comes back in the wrong theme mid-session. Point it at
# the theme we ship. The system copy under /usr/share/icons/default belongs to
# default-cursors, so this user-level one wins without fighting pacman.
setup_cursor_default() {
    local theme_dir="$HOME/.icons/default"
    local index="$theme_dir/index.theme"
    local want="[Icon Theme]
Inherits=${KOOMPI_CURSOR_THEME}"

    if [[ -f "$index" ]] && ! grep -q '^Inherits=' "$index"; then
        warn "$index exists but sets no Inherits=; leaving it alone"
        return 0
    fi
    if [[ -f "$index" ]] && [[ "$(cat "$index")" == "$want" ]]; then
        ok "cursor fallback already points at ${KOOMPI_CURSOR_THEME}"
        return 0
    fi
    info "pointing the default cursor fallback at ${KOOMPI_CURSOR_THEME}"
    if [[ "$DRY_RUN" == true ]]; then return 0; fi
    mkdir -p "$theme_dir"
    printf '%s\n' "$want" > "$index" || { err "could not write $index"; return 1; }
    manifest_add "$index"
}

# GTK apps read their font and dark-mode preference from gsettings, not from
# ~/.config/koompi/config.json, so the defaults have to be pushed once.
setup_toolkit_defaults() {
    step "Toolkit defaults"
    if have gsettings; then
        run gsettings set org.gnome.desktop.interface font-name 'Google Sans Flex Medium 11 @opsz=11,wght=500'
        run gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        run gsettings set org.gnome.desktop.interface cursor-theme "$KOOMPI_CURSOR_THEME"
        run gsettings set org.gnome.desktop.interface cursor-size "$KOOMPI_CURSOR_SIZE"
    else
        warn "gsettings not found; GTK apps keep their stock font and light theme"
    fi
    setup_cursor_default
    if have fc-cache; then
        run fc-cache -f
    fi
    if have update-desktop-database; then
        try update-desktop-database "${XDG_DATA_HOME}/applications" 2>/dev/null || true
    fi
}

setup_system_session() {
    step "System login session"

    # Display managers discover sessions before a user session exists, so most
    # of them do not scan ~/.local/share/wayland-sessions. Keep that user copy
    # as a fallback, but register KOOMPI system-wide for GDM, SDDM and friends.
    local launcher=/usr/local/bin/koompi-session
    local entry=/usr/share/wayland-sessions/koompi.desktop
    local launcher_src="$REPO_ROOT/dots/.local/bin/koompi-session"
    local entry_src="$REPO_ROOT/dots/.local/share/wayland-sessions/koompi.desktop"
    local install_launcher=true

    if [[ -x /usr/bin/koompi-session ]]; then
        launcher=/usr/bin/koompi-session
        install_launcher=false
        ok "packaged /usr/bin/koompi-session present"
    fi

    if $install_launcher && [[ -e "$launcher" ]] \
       && ! grep -q "koompi-session - launch the KOOMPI" "$launcher" 2>/dev/null; then
        warn "$launcher exists and is not KOOMPI-managed; not overwriting it"
        return 0
    fi
    if [[ -e "$entry" ]] && ! grep -q '^X-KOOMPI-Managed=true$' "$entry" 2>/dev/null; then
        warn "$entry exists and is not KOOMPI-managed; not overwriting it"
        return 0
    fi

    local staged_entry
    staged_entry="$(mktemp)"
    sed "s|^Exec=/usr/bin/koompi-session$|Exec=${launcher}|" "$entry_src" > "$staged_entry"

    if $install_launcher; then
        run sudo install -Dm755 "$launcher_src" "$launcher"
    fi
    run sudo install -Dm644 "$staged_entry" "$entry"
    rm -f "$staged_entry"

    # SDDM is pointed at /usr/share/koompi/wayland-sessions so that plasma's and
    # hyprland's own entries never reach the greeter. Link ours into it, or the
    # greeter has nothing to offer. Harmless where SDDM is not the display
    # manager - every other DM still reads $entry.
    local dm_entry=/usr/share/koompi/wayland-sessions/koompi.desktop
    run sudo install -dm755 "$(dirname "$dm_entry")"
    run sudo ln -sfn "$entry" "$dm_entry"
    if [[ -d /etc/sddm.conf.d ]]; then
        run sudo install -Dm644 \
            "$REPO_ROOT/sdata/dist-arch/koompi-session/sddm-sessiondir.conf" \
            /etc/sddm.conf.d/20-koompi-session.conf
    fi

    if [[ "$DRY_RUN" != true && -x "$launcher" && -f "$entry" ]]; then
        mkdir -p "$(dirname "$SYSTEM_MANIFEST")"
        # The drop-in and the link go in the manifest too. Uninstalling the
        # entry while SDDM still reads only the koompi directory would leave a
        # greeter with no session to offer at all.
        if $install_launcher; then
            printf '%s\n%s\n' "$launcher" "$entry" > "$SYSTEM_MANIFEST"
        else
            printf '%s\n' "$entry" > "$SYSTEM_MANIFEST"
        fi
        printf '%s\n' "$dm_entry" >> "$SYSTEM_MANIFEST"
        [[ -f /etc/sddm.conf.d/20-koompi-session.conf ]] \
            && printf '%s\n' /etc/sddm.conf.d/20-koompi-session.conf >> "$SYSTEM_MANIFEST"
        ok "KOOMPI is registered alongside the host desktop"
    fi
}

run_setups() {
    setup_koompi_cli
    setup_globalmenu_rs
    setup_shell_services
    setup_python_venv
    setup_groups_and_modules
    setup_suspend_hook
    setup_low_ram_defaults
    setup_local_ai
    setup_agent_memory
    setup_portals
    setup_toolkit_defaults
    setup_system_session
}
