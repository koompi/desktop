#!/usr/bin/env bash
# koompi update transcript, koompi doctor --last-update, firmware advice (J30: O28 O31).
# Every machine-touching command is shimmed on PATH, script(1) included, so the
# plumbing (env guard, argv, exit line, pruning) is what is under test.
set -uo pipefail

ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
UPDATE="$ROOT/dots/.local/share/koompi/libexec/update"
HEALTH="$ROOT/dots/.local/bin/koompi-health"
fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
command -v flock >/dev/null || { echo "flock not installed; skipping" >&2; exit 0; }

T="$(mktemp -d)"
trap 'rm -rf "$T"' EXIT
mkdir -p "$T/bin" "$T/home/.local/state/koompi" "$T/runtime"
LOGS="$T/home/.local/state/koompi/logs"

cat > "$T/bin/pacman" <<STUB
#!/usr/bin/env bash
printf 'pacman %s\\n' "\$*" >> "$T/order"
if [[ "\$1" == "-Qq" && "\${2:-}" == "koompi-shell" ]]; then exit 0; fi
if [[ "\$1" == "-Qq" ]]; then printf 'koompi-shell 1.1-1\\n'; exit 0; fi
[[ "\$1" == "-Syu" && -e "$T/syu-fails" ]] && { echo "error: failed to commit transaction (conflicting files)"; exit 1; }
exit 0
STUB
cat > "$T/bin/pacman-conf" <<'STUB'
#!/usr/bin/env bash
[[ "${1:-}" == --repo-list ]] && printf 'core\nextra\nkoompi\n'
exit 0
STUB
printf '#!/usr/bin/env bash\nexec "$@"\n' > "$T/bin/sudo"
for tool in paru koompi-hook koompi-snapshot hyprctl setsid; do
    printf '#!/usr/bin/env bash\nprintf "%s %%s\\n" "$*" >> "%s"\nexit 0\n' "$tool" "$T/order" > "$T/bin/$tool"
done
# fwupdmgr: get-updates answers with whatever $T/fw-rc says (0 = updates listed, 2 = none)
cat > "$T/bin/fwupdmgr" <<STUB
#!/usr/bin/env bash
printf 'fwupdmgr %s\\n' "\$*" >> "$T/order"
case "\${1:-}" in
    refresh)     exit 1 ;;   # offline
    get-updates) exit "\$(cat "$T/fw-rc")" ;;
    update)      exit 0 ;;
esac
exit 1
STUB
# script(1): record the call, run the command with stdout+stderr to the terminal
# and the file (like the real one), return its status (-e)
cat > "$T/bin/script" <<STUB
#!/usr/bin/env bash
printf 'script %s\\n' "\$*" >> "$T/order"
[[ "\$1" == -qefc ]] || { echo "script shim: unexpected flags \$1" >&2; exit 99; }
bash -c "\$2" 2>&1 | tee "\$3"
exit "\${PIPESTATUS[0]}"
STUB
cat > "$T/bin/systemd-inhibit" <<'STUB'
#!/usr/bin/env bash
while [[ "${1:-}" == --* ]]; do shift; done
exec "$@"
STUB
cat > "$T/bin/df" <<'STUB'
#!/usr/bin/env bash
printf 'Filesystem 1024-blocks Used Available Capacity Mounted on\n'
printf 'shim 1 1 5000000 1%% /\n'
STUB
printf '#!/usr/bin/env bash\necho 1.0.0-test\n' > "$T/bin/uname"
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pidof"
cat > "$T/bin/loginctl" <<STUB
#!/usr/bin/env bash
case "\${1:-}" in
    list-sessions) printf '3 %s %s seat0 2188 user tty1 no -\\n' "$(id -u)" "$(id -un)" ;;
    show-session)  echo no ;;
esac
STUB
printf '#!/usr/bin/env bash\nexit 1\n' > "$T/bin/pgrep"
chmod +x "$T"/bin/*

export PATH="$T/bin:$PATH"
export HOME="$T/home" XDG_STATE_HOME="$T/home/.local/state" XDG_RUNTIME_DIR="$T/runtime"
export KOOMPI_UPDATE_MODULES_DIR="$T/modules" NO_COLOR=1
unset HYPRLAND_INSTANCE_SIGNATURE KOOMPI_UPDATE_TRANSCRIPT
printf '2\n' > "$T/fw-rc"; : > "$T/order"

run_update() { bash "$UPDATE" "$@" 2>&1 < /dev/null; }
doctor()     { bash "$HEALTH" "$@" 2>&1 < /dev/null; }

# --- dry run: no transcript, no script(1) ----------------------------------
out="$(run_update --dry-run)" || fail "dry run failed: $out"
[[ -e "$LOGS" ]] && fail "a dry run created the log dir: $(ls "$LOGS")"
grep -q '^script ' "$T/order" && fail "a dry run went through script(1): $(cat "$T/order")"
grep -q 'transcript:' <<<"$out" && fail "a dry run printed a transcript path: $out"
grep -q 'would check for firmware updates' <<<"$out" || fail "dry run must say it would check firmware: $out"
grep -q '^fwupdmgr ' "$T/order" && fail "a dry run called fwupdmgr: $(cat "$T/order")"

# --- real run: transcript created, path on the last line, exit line inside --
: > "$T/order"
out="$(run_update --yes)" || fail "packaged update failed: $out"
last="$(tail -1 <<<"$out")"
[[ "$last" == "transcript: ~/.local/state/koompi/logs/update-"*.log ]] \
    || fail "the last line must be the transcript path: '$last'"
log="$LOGS/$(basename "${last#transcript: }")"
[[ -s "$log" ]] || fail "transcript not written: $log"
grep -q '^script -qefc .*--yes' "$T/order" || fail "script(1) did not get the original arguments: $(grep '^script' "$T/order")"
grep -q 'packages up to date (route: packaged)' "$log" || fail "the transcript is missing the update output: $(cat "$log")"
grep -q 'lock taken: ' "$log" || fail "the transcript is missing the inner run's lock line"
[[ "$(tail -1 "$log")" =~ ^koompi\ update:\ exit\ 0\ at\ [0-9]{4}-[0-9]{2}-[0-9]{2}\ [0-9]{2}:[0-9]{2}:[0-9]{2}$ ]] \
    || fail "the transcript's last line must be the exit line: $(tail -1 "$log")"
(( $(grep -c '^script ' "$T/order") == 1 )) || fail "the inner run re-exec'd script(1) again: $(grep '^script' "$T/order")"
grep -q 'firmware: up to date' "$log" || fail "get-updates exit 2 must read as up to date: $(cat "$log")"
grep -q 'koompi update --firmware' "$log" && fail "advice given with no firmware updates listed"
grep -q '^fwupdmgr get-updates --no-unreported-check --no-metadata-check --no-remote-check$' "$T/order" \
    || fail "get-updates must carry the three --no-*-check flags: $(grep fwupdmgr "$T/order")"
grep -q '^fwupdmgr update' "$T/order" && fail "a plain update ran fwupdmgr update"

# --- doctor reads it back; a clean run has no failure pattern ---------------
out="$(doctor --last-update)" || fail "doctor --last-update must exit 0 after a clean update: $out"
grep -qx "transcript: $log" <<<"$out" || fail "doctor did not name the newest transcript: $out"
grep -q '^ended:      koompi update: exit 0 at ' <<<"$out" || fail "doctor did not print the exit line: $out"
grep -qx 'diagnosis:  no known failure pattern' <<<"$out" || fail "a clean transcript must have no diagnosis: $out"

# --- failed run: exit code passes through, transcript holds the failure -----
touch "$T/syu-fails"; : > "$T/order"
out="$(run_update --yes)"
rc=$?
[[ $rc -eq 1 ]] || fail "a failed pacman must fail the update through script(1) (rc=$rc): $out"
[[ "$(tail -1 <<<"$out")" == transcript:* ]] || fail "the transcript path must be last even on failure: $out"
newest="$(printf '%s\n' "$LOGS"/update-*.log | tail -1)"
grep -q 'koompi update: exit 1 at' "$newest" || fail "the failed transcript lacks its exit line: $(tail -2 "$newest")"
out="$(doctor --last-update)"
rc=$?
[[ $rc -eq 1 ]] || fail "doctor --last-update must exit 1 after a failed update (rc=$rc): $out"
grep -q '^diagnosis:  pacman conflict:' <<<"$out" || fail "the pacman failure was not diagnosed: $out"
rm -f "$T/syu-fails"

# --- firmware advice appears only when get-updates lists something ----------
printf '0\n' > "$T/fw-rc"; : > "$T/order"
out="$(run_update --yes)" || fail "update with firmware pending failed: $out"
grep -q "firmware updates are available; apply them with 'koompi update --firmware'" <<<"$out" \
    || fail "advice missing when get-updates listed updates: $out"
grep -q '^fwupdmgr update' "$T/order" && fail "advice must not apply firmware itself"
printf '2\n' > "$T/fw-rc"

# --- --firmware: fwupdmgr update and nothing else ---------------------------
: > "$T/order"
before="$(find "$LOGS" -type f | wc -l)"
out="$(run_update --firmware)" || fail "--firmware failed: $out"
[[ "$(grep -v '^$' "$T/order")" == "fwupdmgr update" ]] \
    || fail "--firmware must call fwupdmgr update and only that: $(cat "$T/order")"
[[ "$(find "$LOGS" -type f | wc -l)" == "$before" ]] || fail "--firmware wrote a transcript"
out="$(PATH="$(dirname "$(command -v bash)")" run_update --firmware)"
rc=$?
{ [[ $rc -eq 1 ]] && grep -q 'fwupd package' <<<"$out"; } || fail "without fwupdmgr, --firmware must name the fwupd package (rc=$rc): $out"

# --- pruning: the newest 10 survive, oldest go first ------------------------
rm -f "$LOGS"/update-*.log
for n in $(seq -w 1 12); do printf 'old %s\n' "$n" > "$LOGS/update-20200101-0000$n.log"; done
out="$(run_update --yes)" || fail "update with 12 old transcripts failed: $out"
count="$(find "$LOGS" -name 'update-*.log' | wc -l)"
[[ "$count" == 10 ]] || fail "expected 10 transcripts after pruning, found $count: $(ls "$LOGS")"
[[ -e "$LOGS/update-20200101-000003.log" ]] && fail "pruning kept the 3rd oldest"
[[ -e "$LOGS/update-20200101-000004.log" ]] || fail "pruning removed the 4th oldest, which should be the oldest kept"
[[ -e "$LOGS/update-20200101-000012.log" ]] || fail "pruning removed the newest fixture"
printf 'keep\n' > "$LOGS/health.log"
run_update --yes >/dev/null || fail "update failed"
[[ "$(cat "$LOGS/health.log")" == keep ]] || fail "pruning touched health.log"

# --- the diagnosis table, one fixture per pattern (CRLF like script(1)) -----
rm -f "$LOGS"/update-*.log
check_pattern() {
    local line="$1" want="$2"
    printf 'Script started on 2026-08-25\r\n%s\r\nkoompi update: exit 1 at 2026-08-25 10:00:00\n' "$line" > "$LOGS/update-20260825-100000.log"
    out="$(doctor --last-update)"
    grep -q "^diagnosis:  $want" <<<"$out" || fail "'$line' was not diagnosed as '$want': $out"
    (( $(grep -c '^diagnosis:' <<<"$out") == 1 )) || fail "'$line' matched more than one pattern: $out"
}
check_pattern 'error: failed to commit transaction (conflicting files)'                        'pacman conflict:'
check_pattern '/usr/lib/libfoo.so exists in filesystem'                                        'pacman conflict:'
check_pattern 'error: failed retrieving file '"'"'core.db'"'"' from mirror : The requested URL returned error: 404' 'a mirror returned 404'
check_pattern 'error: linux: signature from "Dev <d@arch>" is unknown trust'                   'package signatures failed'
check_pattern 'error: could not commit transaction: not enough free disk space'                'the disk is full'
check_pattern 'tar: write error: No space left on device'                                      'the disk is full'
check_pattern '  xx only 1.0 GiB free on /; koompi update needs 2 GiB. Free some space'        'the disk is full'
check_pattern '  xx another koompi update is running (pid 4242)'                               'another koompi update was already running'
check_pattern 'CONFLICT (content): Merge conflict in dots/.config/hypr/hyprland/general.lua'   'the checkout has local changes'
check_pattern 'error: Your local changes to the following files would be overwritten by merge:' 'the checkout has local changes'

# several patterns in one log: one line each; an interrupted run has no exit line
printf 'exists in filesystem\r\nNo space left on device\r\n' > "$LOGS/update-20260825-100001.log"
out="$(doctor --last-update)"
rc=$?
[[ $rc -eq 1 ]] || fail "an interrupted run must exit 1 (rc=$rc): $out"
grep -q '^ended:      no exit line' <<<"$out" || fail "an interrupted run must say so: $out"
(( $(grep -c '^diagnosis:' <<<"$out") == 2 )) || fail "two patterns must give two lines: $out"
grep -qx "transcript: $LOGS/update-20260825-100001.log" <<<"$out" || fail "doctor picked the wrong transcript as newest: $out"

# --- usage and refusal ------------------------------------------------------
bash "$UPDATE" --help | grep -q -- '--firmware' || fail "koompi update --help does not show --firmware"
doctor --help | grep -q -- '--last-update' || fail "koompi doctor --help does not show --last-update"
doctor --help | grep -qi 'never uploaded' || fail "the help must say transcripts are never uploaded"
doctor --bogus >/dev/null 2>&1; [[ $? -eq 2 ]] || fail "an unknown doctor option must exit 2"

printf 'update transcript test passed\n'
