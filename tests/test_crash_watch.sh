#!/usr/bin/env bash
# J40 (OMARCHY-AUDIT O30): koompi-crash-watch follows systemd-coredump's journal
# entries and raises one toast per crashed program; koompi-crash-diagnose
# writes the report and asks the local model, or refuses with a toast when
# there is none. journalctl, busctl, coredumpctl and curl are PATH shims that
# log their argv and play fixtures, and koompi-notify-send is shimmed as a
# sibling (the tools prefer the sibling to PATH), so nothing here reads the
# real journal, talks to the bus, or reaches a server. Proves: the journal
# match, the per-program dedupe window, KOOMPI_CRASH_IGNORE, own-machinery and
# other-uid skips, the exact --exec argv, --once --dry-run sending nothing,
# the report's contents and mode, coredumpctl used read-only, curl aimed only
# at 127.0.0.1, the no-local-model refusal, the unit's shape, and the
# setup_services enable line.
# shellcheck disable=SC2329  # stubs are called from inside setup_services
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_ROOT/dots/.local/bin"
UNIT="$REPO_ROOT/dots/.config/systemd/user/koompi-crash-watch.service"
SETUPS="$REPO_ROOT/sdata/install/setups.sh"
MSG_ID=fc2e22bc6ee647b6b90729ab34a250b1

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }
for tool in jq realpath; do
    command -v "$tool" >/dev/null 2>&1 || fail "$tool is required"
done
[[ -x "$BIN/koompi-crash-watch" ]] || fail "koompi-crash-watch missing or not executable"
[[ -x "$BIN/koompi-crash-diagnose" ]] || fail "koompi-crash-diagnose missing or not executable"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/tools" "$WORK/state"
cp "$BIN/koompi-crash-watch" "$BIN/koompi-crash-diagnose" "$WORK/tools/"
export WORK
export PATH="$WORK/bin:$PATH"

# --- shims -------------------------------------------------------------------

# One line per call, argv words separated by the unit separator.
cat > "$WORK/tools/koompi-notify-send" <<'SHIM'
#!/usr/bin/env bash
{ printf '%s\x1f' "$@"; printf '\n'; } >> "$WORK/notify.log"
SHIM

# Follow / --once: the crash fixtures. Anything else: the diagnose's queries.
cat > "$WORK/bin/journalctl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORK/journalctl.argv"
case " $* " in
    *" --follow "*) cat "$WORK/fixture.jsonl" ;;
    *" --lines=1 "*) tail -n1 "$WORK/fixture.jsonl" ;;
    *" --user "*) printf '2026-08-25T17:00:01+0700 host firefox[4242]: unit fixture line\n' ;;
    *) printf '2026-08-25T17:00:00+0700 host firefox[4242]: process fixture line one\n2026-08-25T17:00:02+0700 host firefox[4242]: process fixture line two\n' ;;
esac
SHIM

cat > "$WORK/bin/busctl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORK/busctl.argv"
case " $* " in
    *" NameHasOwner "*) if [[ -e "$WORK/server-down" ]]; then echo "b false"; else echo "b true"; fi ;;
    *) exit 1 ;;
esac
SHIM

cat > "$WORK/bin/coredumpctl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORK/coredumpctl.argv"
cat <<'INFO'
           PID: 4242 (firefox)
           UID: 1000 (user)
        Signal: 11 (SEGV) si_code: SEGV_MAPERR
  Command Line: /usr/lib/firefox/firefox --new-window
    Executable: /usr/lib/firefox/firefox
          Unit: user@1000.service
     User Unit: app-firefox-123.scope
       Storage: none
       Message: Process 4242 (firefox) of user 1000 dumped core.
INFO
SHIM

# Connection refused: no local model.
cat > "$WORK/bin/curl" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$WORK/curl.argv"
exit 7
SHIM
chmod +x "$WORK"/bin/* "$WORK"/tools/*

entry() {
    # entry <uid> <comm> <pid> <exe|-> <signal>
    jq -cn --arg uid "$1" --arg comm "$2" --arg pid "$3" --arg exe "$4" --arg sig "$5" --arg id "$MSG_ID" \
        '{MESSAGE_ID: $id, _UID: $uid, COREDUMP_UID: $uid, COREDUMP_COMM: $comm, COREDUMP_SIGNAL_NAME: $sig}
         + (if $pid != "-" then {COREDUMP_PID: $pid} else {} end)
         + (if $exe != "-" then {COREDUMP_EXE: $exe} else {} end)'
}
{
    entry "$UID" firefox 4242 /usr/lib/firefox/firefox SIGSEGV
    entry "$UID" firefox 4243 /usr/lib/firefox/firefox SIGSEGV          # same program, inside the window
    entry "$UID" LaTeX 4300 /opt/MicroTeX/LaTeX SIGABRT                  # KOOMPI_CRASH_IGNORE
    entry 99999 evolution 4400 /usr/bin/evolution SIGSEGV               # not this user
    entry "$UID" broken - /usr/bin/broken SIGSEGV                        # no pid: reported, skipped
    entry "$UID" koompi-crash-dia 4500 "$WORK/tools/koompi-crash-diagnose" SIGSEGV  # own machinery
    entry "$UID" noexe 4600 - SIGBUS                                     # no exe: comm is the name
} > "$WORK/fixture.jsonl"

WATCH="$WORK/tools/koompi-crash-watch"
DIAGNOSE="$WORK/tools/koompi-crash-diagnose"
sep=$'\x1f'
expected_firefox="-a${sep}KOOMPI${sep}-u${sep}critical${sep}Process crashed: firefox${sep}SIGSEGV. Click to diagnose with the local model.${sep}--exec${sep}$DIAGNOSE${sep}4242${sep}firefox${sep}/usr/lib/firefox/firefox${sep}SIGSEGV${sep}"
expected_noexe="-a${sep}KOOMPI${sep}-u${sep}critical${sep}Process crashed: noexe${sep}SIGBUS. Click to diagnose with the local model.${sep}--exec${sep}$DIAGNOSE${sep}4600${sep}noexe${sep}-${sep}SIGBUS${sep}"

# --- 1. the follow: match, dedupe, ignore, skips, exact argv -----------------

rm -f "$WORK"/*.argv "$WORK/notify.log"
err="$(KOOMPI_CRASH_IGNORE='^LaTeX$' "$WATCH" 2>&1 >/dev/null)"
rc=$?
(( rc == 0 )) || fail "koompi-crash-watch exited $rc: $err"
grep -qF -- "--quiet --output=json MESSAGE_ID=$MSG_ID COREDUMP_UID=$UID --follow --lines=0" "$WORK/journalctl.argv" \
    || fail "journalctl was not followed with the MESSAGE_ID and COREDUMP_UID match and --lines=0: $(cat "$WORK/journalctl.argv")"
[[ -s "$WORK/notify.log" ]] || fail "no notification was sent"
n="$(wc -l < "$WORK/notify.log")"
(( n == 2 )) || fail "expected 2 notifications (firefox once, noexe), got $n: $(tr '\x1f' ' ' < "$WORK/notify.log")"
[[ "$(sed -n 1p "$WORK/notify.log")" == "$expected_firefox" ]] \
    || fail "firefox argv differs: $(sed -n 1p "$WORK/notify.log" | tr '\x1f' '|')"
[[ "$(sed -n 2p "$WORK/notify.log")" == "$expected_noexe" ]] \
    || fail "noexe argv differs: $(sed -n 2p "$WORK/notify.log" | tr '\x1f' '|')"
grep -q 'without a usable COREDUMP_PID' <<<"$err" || fail "the pid-less entry was dropped silently: $err"
grep -q 'NameHasOwner' "$WORK/busctl.argv" || fail "the watcher did not wait for the notification server"
echo "ok   follow: 7 entries -> 2 toasts (dedupe, ignore, other uid, own machinery, no pid), exact --exec argv"

# --- 2. the window is the reason: with it at 0 the duplicate is announced ----

rm -f "$WORK"/*.argv "$WORK/notify.log"
KOOMPI_CRASH_IGNORE='^LaTeX$' KOOMPI_CRASH_DEDUPE_SECONDS=0 "$WATCH" >/dev/null 2>&1 || fail "watch (dedupe 0) failed"
n="$(wc -l < "$WORK/notify.log")"
(( n == 3 )) || fail "with a 0 s window expected 3 notifications, got $n"
grep -c "${sep}4243${sep}" "$WORK/notify.log" | grep -qx 1 || fail "pid 4243 was not announced once the window was 0"
echo "ok   dedupe: KOOMPI_CRASH_DEDUPE_SECONDS=0 announces the duplicate (3 toasts)"

# --- 3. without the ignore regex LaTeX is announced too ----------------------

rm -f "$WORK"/*.argv "$WORK/notify.log"
"$WATCH" >/dev/null 2>&1 || fail "watch (no ignore) failed"
grep -q "Process crashed: LaTeX" "$WORK/notify.log" || fail "LaTeX was not announced without KOOMPI_CRASH_IGNORE"
echo "ok   ignore: the regex is the only thing keeping LaTeX quiet"

# --- 4. no notification server: bounded wait, nothing sent, said so ----------

rm -f "$WORK"/*.argv "$WORK/notify.log"
touch "$WORK/server-down"
err="$(KOOMPI_CRASH_IGNORE='^LaTeX$' KOOMPI_CRASH_NOTIFY_WAIT=1 "$WATCH" 2>&1 >/dev/null)"
rm -f "$WORK/server-down"
[[ -e "$WORK/notify.log" ]] && fail "a toast was sent with no notification server"
grep -q 'no notification server after 1s' <<<"$err" || fail "the undelivered crash was not reported: $err"
echo "ok   wait: no server -> nothing sent, stderr names the crash"

# --- 5. --once --dry-run: newest entry, nothing sent, no bus call ------------

rm -f "$WORK"/*.argv "$WORK/notify.log"
out="$("$WATCH" --once --dry-run 2>&1)" || fail "--once --dry-run failed: $out"
grep -qF -- "--quiet --output=json MESSAGE_ID=$MSG_ID COREDUMP_UID=$UID --lines=1" "$WORK/journalctl.argv" \
    || fail "--once did not read one entry: $(cat "$WORK/journalctl.argv")"
grep -q -- '--follow' "$WORK/journalctl.argv" && fail "--once still follows"
[[ -e "$WORK/notify.log" ]] && fail "--dry-run sent a notification"
[[ -e "$WORK/busctl.argv" ]] && fail "--dry-run touched the bus"
[[ "$out" == "dry-run: would send: "*"--exec $DIAGNOSE 4600 noexe - SIGBUS" ]] \
    || fail "--dry-run did not print the argv it would send: $out"
echo "ok   --once --dry-run: reads the newest entry, prints the argv, sends nothing"

"$WATCH" --bogus >/dev/null 2>&1; (( $? == 64 )) || fail "an unknown argument is not exit 64"

# --- 6. diagnose: report written, model absent -> refusal --------------------

rm -f "$WORK"/*.argv "$WORK/notify.log"
err="$(XDG_STATE_HOME="$WORK/state" "$DIAGNOSE" 4242 firefox /usr/lib/firefox/firefox SIGSEGV 2>&1 >/dev/null)"
rc=$?
(( rc == 3 )) || fail "diagnose with no local model exited $rc, want 3: $err"
report="$(find "$WORK/state/koompi/crash" -name '*-firefox-4242.md' | head -n1)"
[[ -n "$report" ]] || fail "no report under \$XDG_STATE_HOME/koompi/crash: $(find "$WORK/state" | tr '\n' ' ')"
[[ "$(stat -c %a "$report")" == 600 ]] || fail "report is $(stat -c %a "$report"), want 600 (it holds the command line)"
[[ "$(stat -c %a "$WORK/state/koompi/crash")" == 700 ]] || fail "crash dir is not 700"
for needle in \
    '- process: firefox' '- PID: 4242' '- binary: /usr/lib/firefox/firefox' '- signal: SIGSEGV' \
    '- unit: user@1000.service (user unit: app-firefox-123.scope)' \
    '## coredumpctl info 4242' 'Signal: 11 (SEGV) si_code: SEGV_MAPERR' \
    '## Journal: the process'"'"'s own lines (_COMM=firefox or _PID=4242, last 200)' \
    'process fixture line one' 'process fixture line two' \
    '## Journal: user unit app-firefox-123.scope (last 200)' 'unit fixture line' \
    'Do not invent stack frames'; do
    grep -qF -- "$needle" "$report" || fail "report lacks '$needle':
$(cat "$report")"
done
grep -qFx 'info --no-pager 4242' "$WORK/coredumpctl.argv" || fail "coredumpctl was not called as 'info --no-pager 4242': $(cat "$WORK/coredumpctl.argv")"
[[ "$(wc -l < "$WORK/coredumpctl.argv")" == 1 ]] || fail "coredumpctl was called more than once (read-only means info, once): $(cat "$WORK/coredumpctl.argv")"
grep -qF -- '--no-pager --output=short-iso --lines=200 _COMM=firefox + _PID=4242' "$WORK/journalctl.argv" \
    || fail "the process's journal lines were not asked for: $(cat "$WORK/journalctl.argv")"
grep -qF -- '--user --no-pager --output=short-iso --lines=200 --unit=app-firefox-123.scope' "$WORK/journalctl.argv" \
    || fail "the user unit's journal lines were not asked for: $(cat "$WORK/journalctl.argv")"
# Every URL curl saw is loopback; the tool has no other address to know.
while read -r line; do
    for word in $line; do
        [[ $word == http* && $word != http://127.0.0.1:* ]] && fail "curl was aimed off the machine: $word"
    done
done < "$WORK/curl.argv"
grep -q 'no local model on 127.0.0.1:9379' <<<"$err" || fail "refusal not on stderr: $err"
[[ "$(wc -l < "$WORK/notify.log")" == 1 ]] || fail "expected one refusal toast: $(tr '\x1f' '|' < "$WORK/notify.log")"
toast="$(cat "$WORK/notify.log")"
[[ "$toast" == "-a${sep}KOOMPI${sep}-u${sep}critical${sep}No local model to diagnose the crash of firefox${sep}"*"open it yourself at $report${sep}--exec${sep}xdg-open${sep}$report${sep}" ]] \
    || fail "refusal toast differs: $(tr '\x1f' '|' <<<"$toast")"
echo "ok   diagnose: 0600 report with facts, coredumpctl info (read-only), both journal sections; no model -> Consented refusal toast, exit 3"

# --- 7. diagnose argument and --ask guards ----------------------------------

XDG_STATE_HOME="$WORK/state" "$DIAGNOSE" abc >/dev/null 2>&1; (( $? == 64 )) || fail "a non-numeric pid is not exit 64"
XDG_STATE_HOME="$WORK/state" "$DIAGNOSE" >/dev/null 2>&1; (( $? == 64 )) || fail "no pid is not exit 64"
[[ "$(find "$WORK/state/koompi/crash" -name '*.md' | wc -l)" == 1 ]] || fail "a rejected pid still wrote a report"
err="$("$DIAGNOSE" --ask "$report" 2>&1 </dev/null)"; rc=$?
(( rc == 1 )) || fail "--ask with no model exited $rc, want 1"
grep -q "no local model on 127.0.0.1:9379; the report is at $report" <<<"$err" || fail "--ask refusal message differs: $err"
echo "ok   guards: bad pid 64 without a report, --ask without a model exits 1 naming the report"

# --- 8. the unit ----------------------------------------------------------------

[[ -f "$UNIT" ]] || fail "missing $UNIT"
grep -qx 'PartOf=graphical-session.target' "$UNIT" || fail "unit is not PartOf=graphical-session.target"
grep -qx 'After=graphical-session.target' "$UNIT" || fail "unit is not After=graphical-session.target"
grep -qx 'Restart=on-failure' "$UNIT" || fail "unit is not Restart=on-failure"
grep -qx 'ConditionPathExists=!%h/.local/state/koompi/toggles/crash-watch-off' "$UNIT" || fail "unit lacks the crash-watch-off condition"
grep -qx 'ExecStart=%h/.local/bin/koompi-crash-watch' "$UNIT" || fail "unit does not start koompi-crash-watch"
grep -qx 'WantedBy=graphical-session.target' "$UNIT" || fail "unit is not WantedBy=graphical-session.target"
if command -v systemd-analyze >/dev/null 2>&1; then
    # verify checks that ExecStart exists; point the copy at the tree's script.
    mkdir -p "$WORK/unit"
    sed "s|^ExecStart=%h/.local/bin/koompi-crash-watch|ExecStart=$BIN/koompi-crash-watch|" "$UNIT" > "$WORK/unit/koompi-crash-watch.service"
    out="$(systemd-analyze --user verify "$WORK/unit/koompi-crash-watch.service" 2>&1)" \
        || fail "systemd-analyze --user verify: $out"
    [[ -z "$out" ]] || fail "systemd-analyze --user verify has notes: $out"
    echo "ok   unit: shape pinned, systemd-analyze --user verify clean"
else
    echo "ok   unit: shape pinned (skipping systemd-analyze verify: not installed)"
fi

# --- 9. setup_services enables it, and only with a user manager ----------------

step() { :; }; info() { :; }; ok() { :; }; warn() { printf '%s\n' "$*" >> "$WORK/warn.log"; }
have() { return 0; }
run() { printf '%s\n' "$*" >> "$WORK/run.log"; }
python3() { return 1; }
systemctl() { return 1; }
# shellcheck source=sdata/install/setups.sh
source "$SETUPS" 2>/dev/null || true
declare -F setup_services >/dev/null || fail "setups.sh no longer defines setup_services"
systemd_running() { return 0; }
systemd_user_running() { return 0; }
: > "$WORK/run.log"; : > "$WORK/warn.log"
setup_services
grep -Fxq 'systemctl --user enable koompi-crash-watch' "$WORK/run.log" \
    || fail "setup_services does not enable koompi-crash-watch: $(tr '\n' ';' < "$WORK/run.log")"
grep -Fq 'enable --now koompi-crash-watch' "$WORK/run.log" && fail "setup_services starts koompi-crash-watch with --now"
systemd_user_running() { return 1; }
: > "$WORK/run.log"; : > "$WORK/warn.log"
setup_services
grep -Fq 'koompi-crash-watch' "$WORK/run.log" && fail "setup_services touches koompi-crash-watch without a user manager"
grep -Fq 'koompi-crash-watch' "$WORK/warn.log" || fail "setup_services says nothing about koompi-crash-watch when it cannot enable it"
echo "ok   setup_services: enables koompi-crash-watch (no --now), warns without a user manager"
