#!/usr/bin/env bash
# Ingress default-deny, the two LAN peers it lets through, and the firmware
# refresh timer: the dependency rows, the ufw profile (parsed by ufw's own
# parser when it is here), and what the setup and installer functions run,
# with ufw, systemctl, sudo and pacman shimmed so nothing on the machine moves.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PKG="$ROOT/sdata/dist-arch"
PROFILE="$PKG/koompi-sysdefaults/files/etc/ufw/applications.d/koompi"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# 1. Dependency rows.
# Captured, not piped into grep -q: grep quits on the first match and a
# writer still printing gets SIGPIPE, which pipefail reports as a failure.
depends_of() {
    bash -c 'source "$1" 2>/dev/null; printf "%s\n" "${depends[@]}"' _ "$PKG/$1/PKGBUILD"
}
sysdefaults_deps="$(depends_of koompi-sysdefaults)"
basic_deps="$(depends_of koompi-basic)"
screencapture_deps="$(depends_of koompi-screencapture)"
grep -Fxq ufw <<< "$sysdefaults_deps" \
    || fail "koompi-sysdefaults does not depend on ufw, so its profile is inert"
grep -Fxq fwupd <<< "$basic_deps" \
    || fail "koompi-basic does not depend on fwupd"
grep -Fxq tesseract-data-khm <<< "$screencapture_deps" \
    || fail "koompi-screencapture does not ship Khmer OCR data"
grep -Fxq tesseract-data-eng <<< "$screencapture_deps" \
    || fail "koompi-screencapture lost English OCR data"

# 2. The profile: the exact port lines, and ufw's own parser accepting the
#    file. ufw's python module needs gettext's _ installed, as its CLI does.
[[ -f "$PROFILE" ]] || fail "no ufw profile at $PROFILE"
parsed_ports="$(grep -oE '^ports=.*' "$PROFILE" | sed 's/^ports=//' | paste -sd '|')"
grep -Fxq '[KOOMPI-KDEConnect]' "$PROFILE" || fail "profile has no KOOMPI-KDEConnect section"
grep -Fxq 'ports=1714:1764/tcp|1714:1764/udp' "$PROFILE" || fail "KDE Connect ports are not 1714-1764 tcp+udp"
grep -Fxq '[KOOMPI-LocalSend]' "$PROFILE" || fail "profile has no KOOMPI-LocalSend section"
grep -Fxq 'ports=53317/tcp|53317/udp' "$PROFILE" || fail "LocalSend ports are not 53317 tcp+udp"
if python3 -c 'import ufw.applications' 2>/dev/null; then
    parsed="$(python3 - "$(dirname -- "$PROFILE")" <<'PY'
import gettext, sys
gettext.install("ufw")
import ufw.applications
profiles = ufw.applications.get_profiles(sys.argv[1])
for name in sorted(profiles):
    print(name, " ".join(ufw.applications.get_ports(profiles[name])))
PY
)" || fail "ufw's parser rejected the profile: $parsed"
    [[ "$parsed" == $'KOOMPI-KDEConnect 1714:1764/tcp 1714:1764/udp\nKOOMPI-LocalSend 53317/tcp 53317/udp' ]] \
        || fail "ufw parses the profile as something else: $parsed"
else
    echo "skip: python ufw module not here; profile checked by grep only"
fi

# 3. Shims. sudo records its argv and runs nothing; every other command the
#    functions may reach answers as a machine with ufw, no firewalld, no sshd.
shims="$tmp/bin"; mkdir -p "$shims"
log="$tmp/calls"
printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$log" > "$shims/sudo"
printf '#!/usr/bin/env bash\nprintf "ufw %%s\\n" "$*" >> "%s"\n' "$log" > "$shims/ufw"
printf '#!/usr/bin/env bash\nexit 1\n' > "$shims/pacman"
# Queries are not logged: --dry-run may ask, it may not act.
cat > "$shims/systemctl" <<SHIM
#!/usr/bin/env bash
case "\$1" in
    is-active) exit 3 ;;
    list-unit-files) [[ "\$2" == fwupd-refresh.timer || "\$2" == bluetooth.service ]] ;;
    *) printf 'systemctl %s\n' "\$*" >> "$log" ;;
esac
SHIM
chmod 755 "$shims"/*

# The ./setup functions, sourced with the real helpers so run() and try() are
# what --dry-run actually goes through.
run_setup() { # DRY_RUN function
    : > "$log"
    (
        export PATH="$shims:$PATH" DRY_RUN="$1" ASSUME_YES=true REPO_ROOT="$ROOT" OS_GROUP_ID=arch NO_COLOR=1
        cd "$ROOT" || exit 1
        # shellcheck source=../sdata/lib/common.sh
        source sdata/lib/common.sh
        # shellcheck source=../sdata/install/setups.sh
        source sdata/install/setups.sh
        systemd_running() { return 0; }
        systemd_user_running() { return 1; }
        "$2"
    ) < /dev/null 2>&1
}
expect_call() {
    grep -Fxq -- "$1" "$log" || fail "never ran '$1'; ran: $(tr '\n' ';' < "$log")"
}

out="$(run_setup false setup_firewall_defaults)" || fail "setup_firewall_defaults failed: $out"
expect_call "ufw default deny incoming"
expect_call "ufw default allow outgoing"
expect_call "ufw --force enable"
expect_call "systemctl enable ufw.service"
# From git the rules are raw ports (a profile file under /etc would collide
# with the package later); each port the profile names must be opened, and
# nothing else.
opened="$(grep -oE '^ufw allow [0-9:]+/(tcp|udp)' "$log" | sed 's/^ufw allow //' | sort)"
[[ "$opened" == "$(tr '|' '\n' <<< "$parsed_ports" | sort)" ]] \
    || fail "from-git opens '$(tr '\n' ' ' <<< "$opened")' but the profile names '$parsed_ports'"
grep -Fq '/etc/ufw/applications.d' "$log" && fail "wrote under /etc/ufw/applications.d, which the package owns later"
grep -Fq 'ufw allow ssh' "$log" && fail "opened ssh with no sshd running"
grep -Fq 'pacman' "$log" && fail "tried to install ufw when it is on PATH"
# Rules before enable, or the firewall's first moments are deny-only.
[[ "$(grep -n 'ufw allow 53317/udp' "$log" | cut -d: -f1)" -lt "$(grep -n 'ufw --force enable' "$log" | cut -d: -f1)" ]] \
    || fail "ufw enabled before the allow rules were written"

out="$(run_setup true setup_firewall_defaults)" || fail "dry run failed: $out"
[[ ! -s "$log" ]] || fail "--dry-run still ran: $(tr '\n' ';' < "$log")"
for want in '$ sudo ufw default deny incoming' '$ sudo ufw allow 1714:1764/tcp' \
            '$ sudo ufw allow 53317/udp' '$ sudo ufw --force enable' '$ sudo systemctl enable ufw.service'; do
    grep -Fq -- "$want" <<< "$out" || fail "--dry-run does not print '$want': $out"
done

# sshd running: the rule that keeps a remote setup session alive.
sed -i 's/is-active) exit 3 ;;/is-active) [[ "$3" == sshd ]] || exit 3 ;;/' "$shims/systemctl"
out="$(run_setup false setup_firewall_defaults)" || fail "setup_firewall_defaults with sshd failed: $out"
expect_call "ufw allow ssh"
# firewalld running: hands off.
sed -i 's/is-active) .* ;;/is-active) exit 0 ;;/' "$shims/systemctl"
out="$(run_setup false setup_firewall_defaults)" || fail "setup_firewall_defaults with firewalld failed: $out"
grep -Fq 'ufw' "$log" && fail "wrote ufw rules beside an active firewalld"
grep -Fq 'firewalld' <<< "$out" || fail "did not say why the firewall step was skipped"

# 4. The fwupd timer enable in setup_services, same shims.
out="$(run_setup false setup_services)" || fail "setup_services failed: $out"
expect_call "systemctl enable fwupd-refresh.timer"

# 5. The installer half: rules, ENABLED=yes, both units. Its ufw.conf is a
#    temp file, as test_grub_quiet.sh does for grub.cfg.
conf="$tmp/ufw.conf"; printf 'ENABLED=no\nLOGLEVEL=low\n' > "$conf"
: > "$log"
out="$(
    export PATH="$shims:$PATH" KOOMPI_UFW_CONF="$conf"
    # shellcheck source=../installer/src/post_install.sh
    source "$ROOT/installer/src/post_install.sh"
    setup_firewall && enable_firmware_refresh
)" || fail "post_install firewall steps failed: $out"
expect_call "ufw default deny incoming"
expect_call "ufw allow KOOMPI-KDEConnect"
expect_call "ufw allow KOOMPI-LocalSend"
expect_call "systemctl enable ufw.service"
expect_call "systemctl enable fwupd-refresh.timer"
grep -Fq 'ufw enable' "$log" && fail "post_install ran 'ufw enable' inside the chroot"
grep -Fxq 'ENABLED=yes' "$conf" || fail "post_install left ENABLED=no in ufw.conf"
grep -Fxq 'LOGLEVEL=low' "$conf" || fail "post_install clobbered the rest of ufw.conf"

# 6. The preset and run_setups say the same as the scripts.
preset="$PKG/koompi-sysdefaults/files/usr/lib/systemd/system-preset/80-koompi-sysdefaults.preset"
grep -Fxq 'enable ufw.service' "$preset" || fail "preset does not enable ufw.service"
grep -Fxq 'enable fwupd-refresh.timer' "$preset" || fail "preset does not enable fwupd-refresh.timer"
sed -n '/^run_setups() {/,/^}/p' "$ROOT/sdata/install/setups.sh" | grep -Fxq '    setup_firewall_defaults' \
    || fail "run_setups never calls setup_firewall_defaults"

echo "ok test_firewall_defaults.sh"
