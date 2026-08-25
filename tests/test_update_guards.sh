#!/usr/bin/env bash
# koompi update guards (J24: O02 O10 O21); every machine-touching command is shimmed on PATH
# flock stays real: the second-run refusal is a real conflict, not a shim saying busy
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$ROOT/dots/.local/share/koompi/libexec/update"
RELOAD="$ROOT/dots/.local/bin/koompi-reload"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v flock >/dev/null || { echo "flock not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
FAKE_QS_PID=""; FAKE_HYPR_PID=""; FIRST_PID=""
cleanup() {
    touch "$T/release"
    [[ -n "$FIRST_PID" ]] && wait "$FIRST_PID" 2>/dev/null
    for p in "$FAKE_QS_PID" "$FAKE_HYPR_PID"; do
        [[ -n "$p" ]] && { kill "$p" 2>/dev/null; wait "$p" 2>/dev/null; }
    done
    rm -rf "$T"
}
trap cleanup EXIT
mkdir -p "$T/bin" "$T/home/.local/state/koompi" "$T/runtime" \
         "$T/modules/1.0.0-test" "$T/modules/1.0.1-test"
touch "$T/modules/1.0.0-test/vmlinuz" "$T/modules/1.0.1-test/vmlinuz"

cat > "$T/bin/pacman" <<STUB
#!/usr/bin/env bash
printf 'pacman %s\\n' "\$*" >> "$T/order"
if [[ "\$1" == "-Qq" && "\${2:-}" == "koompi-shell" ]]; then exit 0; fi
if [[ "\$1" == "-Qq" ]]; then printf 'koompi-shell 1.1-1\\n'; exit 0; fi
if [[ "\$1" == "-Syu" ]]; then
    touch "$T/syu-ran"
    if [[ -e "$T/block" ]]; then
        touch "$T/syu-started"
        until [[ -e "$T/release" ]]; do sleep 0.1; done
    fi
fi
exit 0
STUB
cat > "$T/bin/pacman-conf" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == --repo-list ]] && printf 'core\nextra\nkoompi\n'
exit 0
STUB
printf '#!/usr/bin/env bash\nexec "$@"\n' > "$T/bin/sudo"
for tool in paru yay koompi-hook koompi-snapshot; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "%s"\nexit 0\n' "$tool" "$T/order" > "$T/bin/$tool"
done
printf '#!/usr/bin/env bash\nprintf "git %%s\\n" "$*" >> "%s"\nexit 0\n' "$T/order" > "$T/bin/git"

cat > "$T/bin/systemd-inhibit" <<STUB
#!/usr/bin/env bash
printf 'inhibit %s\\n' "\$*" >> "$T/order"
while [[ "\${1:-}" == --* ]]; do shift; done
exec "\$@"
STUB
cat > "$T/bin/df" <<STUB
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\\n'
printf 'shim 1 1 %s 1%% /\\n' "\$(cat "$T/avail")"
STUB
printf '#!/usr/bin/env bash\ncat "%s"\n' "$T/kernel" > "$T/bin/uname"
printf '#!/usr/bin/env bash\n[[ -s "%s" ]] || exit 1\ncat "%s"\n' "$T/hypr-pid" "$T/hypr-pid" > "$T/bin/pidof"
cat > "$T/bin/loginctl" <<STUB
#!/usr/bin/env bash
case "\${1:-}" in
    list-sessions) printf '3 %s %s seat0 2188 user tty1 no -\\n' "$(id -u)" "$(id -un)" ;;
    show-session)  cat "$T/locked" ;;
esac
STUB
printf '#!/usr/bin/env bash\nprintf "hyprctl %%s\\n" "$*" >> "%s"\nexit 0\n' "$T/order" > "$T/bin/hyprctl"
printf '#!/usr/bin/env bash\nprintf "setsid %%s\\n" "$*" >> "%s"\nexit 0\n' "$T/order" > "$T/bin/setsid"
cat > "$T/bin/killall" <<STUB
#!/usr/bin/env bash
for arg in "\$@"; do case "\$arg" in -*|--) ;; *) printf '%s\\n' "\$arg" >> "$T/killall-log" ;; esac; done
exit 0
STUB
chmod +x "$T"/bin/*
ln -s "$(command -v bash)" "$T/bin/qs"
# real /proc entry for count_shells; reaps its sleep on TERM or an orphan holds stdout open for 300s
"$T/bin/qs" -c "trap 'kill \$s' TERM; sleep 300 & s=\$!; wait" -c koompi &
FAKE_QS_PID=$!
cat > "$T/bin/pgrep" <<STUB
#!/usr/bin/env bash
case "\${!#}" in
    qs) printf '%s\\n' "$FAKE_QS_PID"; exit 0 ;;
esac
exit 1
STUB
chmod +x "$T/bin/pgrep"

printf '%s\n' 5000000 > "$T/avail"   # KiB, ~4.8 GiB
printf '%s\n' 1.0.1-test > "$T/kernel"
printf '%s\n' no > "$T/locked"
: > "$T/order"; : > "$T/killall-log"

export PATH="$T/bin:$PATH"
export HOME="$T/home" XDG_STATE_HOME="$T/home/.local/state" XDG_RUNTIME_DIR="$T/runtime"
export KOOMPI_UPDATE_MODULES_DIR="$T/modules" NO_COLOR=1
unset HYPRLAND_INSTANCE_SIGNATURE

run_update() { bash "$UPDATE" "$@" 2>&1 < /dev/null; }
line_of() { grep -n -- "$1" <<<"$2" | head -1 | cut -d: -f1; }

out="$(run_update --dry-run)"
rc=$?
[[ $rc -eq 0 ]] || fail "dry run failed (rc=$rc): $out"
l_lock="$(line_of 'lock taken: ' "$out")"
l_inh="$(line_of 'systemd-inhibit --what=sleep:idle:handle-lid-switch' "$out")"
l_df="$(line_of 'free space on /: 4.8 GiB' "$out")"
[[ -n "$l_lock" && -n "$l_inh" && -n "$l_df" ]] \
    || fail "dry run is missing the lock, inhibit or free-space line: $out"
(( l_lock < l_inh && l_inh < l_df )) \
    || fail "guard lines out of order (lock $l_lock, inhibit $l_inh, space $l_df): $out"
grep -q 'lock taken: .*/koompi-update.lock (pid [0-9]*)' <<<"$out" \
    || fail "the lock line does not name the file and pid: $out"
[[ -e "$T/syu-ran" ]] && fail "a dry run ran pacman -Syu"
grep -q '^inhibit ' "$T/order" && fail "a dry run took a real inhibitor"

touch "$T/block"
run_update --yes > "$T/first.out" &
FIRST_PID=$!
for _ in $(seq 100); do [[ -e "$T/syu-started" ]] && break; sleep 0.1; done
[[ -e "$T/syu-started" ]] || fail "the first run never reached pacman -Syu: $(cat "$T/first.out")"
before="$(wc -l < "$T/order")"
out="$(run_update --dry-run)"
rc=$?
[[ $rc -eq 1 ]] || fail "a second run must exit 1 while another holds the lock (rc=$rc): $out"
grep -qE 'another koompi update is running \(pid [0-9]+\)' <<<"$out" \
    || fail "the refusal must name the running update's pid: $out"
holder="$(grep -oE 'pid [0-9]+' <<<"$out" | grep -oE '[0-9]+')"
kill -0 "$holder" 2>/dev/null || fail "the pid in the refusal ($holder) is not a live process"
[[ "$(wc -l < "$T/order")" == "$before" ]] \
    || fail "the refused run touched pacman or git: $(tail -n +"$((before + 1))" "$T/order")"
touch "$T/release"
wait "$FIRST_PID" || fail "the first run failed: $(cat "$T/first.out")"
FIRST_PID=""
rm -f "$T/block" "$T/release" "$T/syu-started"
grep -q 'inhibit --what=sleep:idle:handle-lid-switch --mode=block --who=koompi-update' "$T/order" \
    || fail "the upgrade did not run under systemd-inhibit: $(cat "$T/order")"
l_inh="$(grep -n '^inhibit ' "$T/order" | head -1 | cut -d: -f1)"
l_syu="$(grep -n '^pacman -Syu' "$T/order" | head -1 | cut -d: -f1)"
(( l_inh < l_syu )) || fail "the inhibitor was taken after pacman -Syu (lines $l_inh vs $l_syu)"
out="$(run_update --dry-run)" || fail "the lock outlived the run that took it: $out"

rm -f "$T/syu-ran"; : > "$T/order"
printf '%s\n' 1000000 > "$T/avail"   # KiB, ~0.95 GiB
out="$(run_update --yes)"
rc=$?
[[ $rc -eq 1 ]] || fail "low free space must fail the update (rc=$rc): $out"
grep -q 'only 1.0 GiB free on /; koompi update needs 2 GiB' <<<"$out" \
    || fail "the free-space refusal must state both numbers: $out"
[[ -e "$T/syu-ran" ]] && fail "pacman -Syu ran with less than 2 GiB free"
grep -q '^pacman -Syu' "$T/order" && fail "pacman -Syu was invoked despite low space"
printf '%s\n' 5000000 > "$T/avail"

export HYPRLAND_INSTANCE_SIGNATURE=test-session
printf '%s\n' 1.0.0-test > "$T/kernel"
: > "$T/killall-log"
out="$(run_update --yes)" || fail "packaged update with a kernel mismatch failed: $out"
grep -q 'reboot needed: kernel 1.0.1-test is installed but 1.0.0-test is running' <<<"$out" \
    || fail "a newer installed kernel must print the reboot line: $out"
grep -q 'shell restarted' <<<"$out" \
    && fail "'shell restarted' must give way to the reboot advice: $out"
grep -qx 'qs' "$T/killall-log" || fail "the shell was not reloaded on the kernel-mismatch run"

cp "$(command -v sleep)" "$T/hypr-bin"
"$T/hypr-bin" 300 < /dev/null > /dev/null 2>&1 &
FAKE_HYPR_PID=$!
rm -f "$T/hypr-bin"
printf '%s\n' "$FAKE_HYPR_PID" > "$T/hypr-pid"
printf '%s\n' 1.0.1-test > "$T/kernel"
out="$(run_update --yes)" || fail "packaged update with a replaced Hyprland failed: $out"
grep -q 'reboot needed: the Hyprland binary was replaced' <<<"$out" \
    || fail "a deleted Hyprland exe must print the reboot line: $out"
: > "$T/hypr-pid"

out="$(run_update --yes)" || fail "packaged update failed: $out"
grep -q 'shell restarted' <<<"$out" || fail "an ordinary reload must still report the restart: $out"
grep -q 'reboot needed' <<<"$out" && fail "a reboot was advised with nothing to reboot for: $out"

printf '%s\n' yes > "$T/locked"
: > "$T/killall-log"
out="$(run_update --yes)" || fail "the update itself must still succeed under a lock: $out"
grep -q "session is locked; the shell was not restarted. Unlock and run 'koompi reload'" <<<"$out" \
    || fail "a locked session must refuse the reload with the koompi reload advice: $out"
[[ -s "$T/killall-log" ]] && fail "qs was killed under a locked session: $(cat "$T/killall-log")"

out="$(bash "$RELOAD" 2>&1 < /dev/null)"
rc=$?
[[ $rc -eq 1 ]] || fail "koompi-reload must exit 1 under a locked session (rc=$rc): $out"
grep -q "session is locked; unlock and run 'koompi reload'" <<<"$out" \
    || fail "koompi-reload must say why it refused: $out"
[[ -s "$T/killall-log" ]] && fail "koompi-reload killed qs under a locked session"

printf '%s\n' no > "$T/locked"
: > "$T/order"
out="$(bash "$RELOAD" 2>&1 < /dev/null)" || fail "koompi-reload failed while unlocked: $out"
grep -qx 'qs' "$T/killall-log" || fail "koompi-reload did not stop qs while unlocked"
grep -q '^setsid env QT_QPA_PLATFORM=wayland qs -c koompi' "$T/order" \
    || fail "koompi-reload did not restart the shell: $(cat "$T/order")"
grep -qE 'global-menu-daemon|quickshell' "$T/killall-log" \
    && fail "koompi-reload handed killall a name that was not running: $(cat "$T/killall-log")"

printf 'update guards test passed\n'
