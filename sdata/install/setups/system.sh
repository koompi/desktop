# shellcheck shell=bash
# Sourced by sdata/install/setups.sh. Groups, kernel modules, suspend hook, low-RAM defaults, user and system services.

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
    # The body is the hook script itself: $1 and $STAMP must reach /bin/sh
    # unexpanded, so the single quotes are the point.
    # shellcheck disable=SC2016
    sudo_write "$hook" '#!/bin/sh
# Installed by KOOMPI. See setup_suspend_hook in sdata/install/setups/system.sh.
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

# DMI-gated hardware quirks (OMARCHY-AUDIT O08), the runner koompi-shell ships,
# run from the checkout: it finds sdata/hardware and dots/.local/bin itself.
# dry run is the runner's own: real decisions for this machine, no sudo.
setup_hardware_quirks() {
    step "Hardware quirks"
    local runner="$REPO_ROOT/dots/.local/share/koompi/libexec/apply-hardware"
    [[ -x "$runner" ]] || { warn "$runner missing; hardware quirks skipped"; return 0; }
    if [[ "$DRY_RUN" == true ]]; then
        "$runner" --dry-run || warn "a hardware quirk failed its dry run"
        return 0
    fi
    try sudo "$runner" \
        || warn "a hardware quirk failed; see /var/log/koompi/hardware.log"
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
    local src="$REPO_ROOT/sdata/dist-arch/koompi-sysdefaults/files/usr/lib" file files=()
    mapfile -d '' files < <(find "$src" -type f -print0)
    (( ${#files[@]} )) || die "no files under $src"
    for file in "${files[@]}"; do
        run sudo install -Dm644 "$file" "/usr/local/lib/${file#"$src/"}"
    done

    # boot-time oneshot: nothing above re-runs it, so from git the drop-in
    # waits for a reboot while pacman's 25-systemd-sysctl.hook applies it now.
    # restart re-reads the whole sysctl.d search path on purpose - that path is
    # the precedence rule, and poking single keys would impose values an
    # admin's /etc/sysctl.d/ file shadows. try(): /proc/sys is read-only in a
    # container, which is not a reason to abort an install.
    if try sudo systemctl restart systemd-sysctl.service; then
        ok "kernel variables applied (swappiness, dirty limits, inotify watches)"
    else
        warn "could not apply the kernel variables now; they take effect at the next boot"
    fi

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

# refuses with exit 0 where it cannot apply (ext4, no mkinitcpio), so runs everywhere;
# its own --dry-run needs no root and prints the plan for this machine
setup_hibernation() {
    step "Hibernation (btrfs swapfile, resume hook, kernel cmdline)"
    systemd_running || { info "no running systemd; skipping"; return 0; }
    local script="$REPO_ROOT/dots/.local/share/koompi/libexec/hibernation-setup"
    [[ -x "$script" ]] || { warn "$script missing or not executable; skipping hibernation"; return 0; }
    if [[ "$DRY_RUN" == true ]]; then
        "$script" --dry-run || warn "hibernation dry run failed; see above"
        return 0
    fi
    try sudo "$script" \
        || warn "hibernation setup failed; Hibernate stays off the session screen until 'sudo $script' succeeds"
}

# Raw ports rather than the package's profile names: ufw reads profiles from
# /etc/ufw/applications.d only (config_dir in ufw/common.py), and a file put
# there from git makes a later package install fail on "exists in filesystem".
# tests/test_firewall_defaults.sh holds these to the profile's ports.
setup_firewall_defaults() {
    step "Firewall: deny incoming, allow KDE Connect and LocalSend"
    systemd_running || { info "no running systemd; skipping"; return 0; }
    if systemctl is-active --quiet firewalld; then
        warn "firewalld is active; leaving it in charge rather than running two firewalls"
        return 0
    fi
    if ! have ufw; then
        case "$OS_GROUP_ID" in
            arch)   run sudo pacman -S --needed --noconfirm ufw ;;
            fedora) run sudo dnf install -y ufw ;;
            debian) run sudo apt-get install -y ufw ;;
            *)      warn "ufw is not installed; incoming connections stay open"; return 0 ;;
        esac
    fi

    # ufw skips an existing rule: re-runs change nothing
    run sudo ufw default deny incoming
    run sudo ufw default allow outgoing
    run sudo ufw allow 1714:1764/tcp comment 'KDE Connect'
    run sudo ufw allow 1714:1764/udp comment 'KDE Connect'
    run sudo ufw allow 53317/tcp comment 'LocalSend'
    run sudo ufw allow 53317/udp comment 'LocalSend'
    # a setup run over ssh must not cut its own session
    if systemctl is-active --quiet sshd; then
        info "sshd is running; keeping ssh reachable"
        run sudo ufw allow ssh
    fi
    # --force skips the ssh-disruption prompt; on Arch `ufw enable` leaves the unit alone
    run sudo ufw --force enable
    run sudo systemctl enable ufw.service
    ok "incoming denied, KDE Connect and LocalSend allowed"
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
    # koompi-basic dep, so packaged users have it and the preset enables this
    # timer; from git nothing pulls fwupd in
    if ! have fwupdmgr; then
        case "$OS_GROUP_ID" in
            arch)   run sudo pacman -S --needed --noconfirm fwupd ;;
            fedora) run sudo dnf install -y fwupd ;;
            debian) run sudo apt-get install -y fwupd ;;
            *)      warn "no fwupd recipe for this distro; firmware updates stay manual" ;;
        esac
    fi
    if systemctl list-unit-files fwupd-refresh.timer >/dev/null 2>&1; then
        run sudo systemctl enable fwupd-refresh.timer
    else
        warn "fwupd is not installed; firmware updates stay manual"
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

    # Follows this user's coredumps and offers a local diagnosis (O30). Without
    # --now, same as the two above: WantedBy=graphical-session.target.
    if ! systemd_user_running; then
        warn "no user systemd manager here; enable koompi-crash-watch after your next login"
    else
        run systemctl --user enable koompi-crash-watch
    fi
}
