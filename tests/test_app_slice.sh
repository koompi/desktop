#!/usr/bin/env bash
# Everything Hyprland execs sits in the logind session scope, which systemd-oomd
# never considers, so on a small machine memory pressure takes the whole session.
# koompi-launch starts each app as its own app-<id>-<n>.scope in the user
# manager's app.slice instead. Asserts the wrapper keeps argv byte-for-byte,
# expands desktop-entry field codes, honours Path= and Terminal=, says so when it
# has to run without a user manager, and, where one is live, lands the process in
# app.slice. Then that the shell's launch paths actually go through it.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCH="$REPO_ROOT/dots/.local/bin/koompi-launch"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
KEYBINDS="$REPO_ROOT/dots/.config/hypr/hyprland/keybinds.lua"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }

[[ -x "$LAUNCH" ]] || { echo "FAIL: $LAUNCH is not executable" >&2; exit 1; }

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

cat > "$tmp/argdump" <<'EOF'
#!/usr/bin/env bash
{
    printf 'cwd=%s\n' "$PWD"
    printf 'wd=%s\n' "${WAYLAND_DISPLAY:-}"
    printf 'cg=%s\n' "$(cut -d: -f3 /proc/self/cgroup)"
    printf '[%s]\n' "$@"
} > "$OUT"
EOF
cat > "$tmp/fakeTerm" <<'EOF'
#!/usr/bin/env bash
printf '[%s]\n' "$@" > "$TOUT"
shift 2
exec "$@"
EOF
chmod +x "$tmp/argdump" "$tmp/fakeTerm"

expect_args() {
    local out=$1 want got
    shift
    want="$(printf '[%s]\n' "$@")"
    got="$(grep '^\[' "$out")"
    [[ "$got" == "$want" ]] || fail "argv differs:
want:
$want
got:
$got"
}

# 1. raw argv: spaces, empty, quotes, dollar and a literal %u all survive untouched
OUT="$tmp/o1" WAYLAND_DISPLAY=wl-test "$LAUNCH" "$tmp/argdump" 'a b' '' 'c"d' "\$HOME" '%u' 2>"$tmp/e1" \
    || fail "raw launch exited $?: $(cat "$tmp/e1")"
expect_args "$tmp/o1" 'a b' '' 'c"d' "\$HOME" '%u'
grep -qx 'wd=wl-test' "$tmp/o1" || fail "the session environment did not reach the app: $(grep '^wd=' "$tmp/o1")"

# 2. desktop entry: quoting, escapes, every field code that expands, Path=
mkdir -p "$tmp/share/applications" "$tmp/work"
cat > "$tmp/share/applications/probe.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Probe App
Icon=probe-icon
Exec=$tmp/argdump %i %c "quoted \\\\"arg\\\\"" --url=%u %u %% tab\\there %k %d
Path=$tmp/work

[Desktop Action other]
Name=Other
Exec=/bin/false
EOF
OUT="$tmp/o2" XDG_DATA_HOME="$tmp/share" "$LAUNCH" probe.desktop 'https://example.org/a b' 2>"$tmp/e2" \
    || fail "desktop launch exited $?: $(cat "$tmp/e2")"
expect_args "$tmp/o2" --icon probe-icon 'Probe App' 'quoted "arg"' '--url=https://example.org/a b' \
    'https://example.org/a b' '%' $'tab\there' "$tmp/share/applications/probe.desktop"
grep -qx "cwd=$tmp/work" "$tmp/o2" || fail "Path= was not honoured: $(grep '^cwd=' "$tmp/o2")"

# 3. %F takes every file, Terminal=true wraps in $TERMINAL as TERM -e CMD...
cat > "$tmp/share/applications/multi.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Multi
Terminal=true
Exec=$tmp/argdump %F
EOF
OUT="$tmp/o3" TOUT="$tmp/t3" TERMINAL="$tmp/fakeTerm -x" XDG_DATA_HOME="$tmp/share" \
    "$LAUNCH" multi.desktop 'f 1' f2 2>"$tmp/e3" || fail "terminal launch exited $?: $(cat "$tmp/e3")"
expect_args "$tmp/t3" -x -e "$tmp/argdump" 'f 1' f2
expect_args "$tmp/o3" 'f 1' f2

# 4. --terminal wins over TERMINAL, --cwd over Path=, and both apply to a raw command too
OUT="$tmp/o4" TOUT="$tmp/t4" TERMINAL=/nonexistent "$LAUNCH" --cwd "$tmp/work" --terminal "$tmp/fakeTerm -y" "$tmp/argdump" z 2>"$tmp/e4" \
    || fail "--terminal launch exited $?: $(cat "$tmp/e4")"
expect_args "$tmp/t4" -y -e "$tmp/argdump" z
grep -qx "cwd=$tmp/work" "$tmp/o4" || fail "--cwd was not honoured: $(grep '^cwd=' "$tmp/o4")"
OUT="$tmp/o4b" XDG_DATA_HOME="$tmp/share" "$LAUNCH" --cwd "$tmp" probe.desktop 2>"$tmp/e4b" || fail "--cwd desktop launch exited $?"
grep -qx "cwd=$tmp" "$tmp/o4b" || fail "--cwd did not override Path=: $(grep '^cwd=' "$tmp/o4b")"
OUT="$tmp/o4c" "$LAUNCH" --cwd "$tmp/missing" "$tmp/argdump" 2>"$tmp/e4c" || fail "a missing --cwd must not stop the launch"
grep -q 'cannot enter' "$tmp/e4c" || fail "a missing --cwd was swallowed silently"

# 5. a missing entry is an error, not a silent no-op
if "$LAUNCH" nope.desktop 2>"$tmp/e5"; then fail "an unknown desktop entry launched something"; fi
grep -q 'no desktop entry named nope.desktop' "$tmp/e5" || fail "unknown entry: no message on stderr"

# 6. without a user manager the app still starts and the fallback is said out loud
mkdir -p "$tmp/rt"
OUT="$tmp/o6" XDG_RUNTIME_DIR="$tmp/rt" "$LAUNCH" "$tmp/argdump" fallback 2>"$tmp/e6" \
    || fail "fallback launch exited $?: $(cat "$tmp/e6")"
expect_args "$tmp/o6" fallback
grep -q 'no user manager' "$tmp/e6" || fail "fallback engaged silently (stderr: $(cat "$tmp/e6"))"

# 7. with a live user manager, a launched sleep lives in app.slice/app-<id>-<n>.scope
state="$(systemctl --user is-system-running 2>/dev/null || true)"
if [[ "$state" == running || "$state" == degraded ]]; then
    "$LAUNCH" --id probe-x sleep 30 &
    pid=$!
    for _ in $(seq 1 50); do
        [[ "$(cat "/proc/$pid/comm" 2>/dev/null)" == sleep ]] && break
        sleep 0.1
    done
    cg="$(cut -d: -f3 "/proc/$pid/cgroup" 2>/dev/null)"
    kill "$pid" 2>/dev/null
    wait "$pid" 2>/dev/null
    [[ "$cg" =~ /app\.slice/app-probe\\x2dx-[0-9]+\.scope$ ]] \
        || fail "launched sleep is in '$cg', not app.slice/app-probe\\x2dx-<n>.scope"
    grep -q '/app.slice/app-argdump-[0-9]*.scope$' "$tmp/o1" \
        || fail "raw launch is in '$(grep '^cg=' "$tmp/o1")', not app.slice"
else
    echo "skipping cgroup check: no user manager (systemctl --user is-system-running: ${state:-none})"
fi

# 8. the shell's launch paths use it: no DesktopEntry.execute() left at the
#    Search, Launchpad and dock call sites, and every App: bind goes through app()
for qml in services/LauncherSearch.qml modules/koompi/launchpad/LaunchpadContent.qml modules/koompi/dock/DockAppButton.qml; do
    file="$SHELL_ROOT/$qml"
    if grep -nE '(entry|desktopEntry|action)\??\.execute\(\)' "$file"; then
        fail "$qml still calls DesktopEntry.execute(), which cannot reach app.slice"
    fi
done
grep -q 'koompi-launch' "$SHELL_ROOT/services/LauncherSearch.qml" || fail "LauncherSearch.qml no longer launches through koompi-launch"
grep -q 'LauncherSearch.launch(' "$SHELL_ROOT/modules/koompi/launchpad/LaunchpadContent.qml" || fail "LaunchpadContent.qml does not use LauncherSearch.launch"
grep -q 'LauncherSearch.launch(' "$SHELL_ROOT/modules/koompi/dock/DockAppButton.qml" || fail "DockAppButton.qml does not use LauncherSearch.launch"

grep -q 'exec_cmd("koompi-launch --id "' "$KEYBINDS" || fail "keybinds.lua: app() no longer wraps koompi-launch"
while IFS= read -r line; do
    grep -qE 'app\(|koompi-launch' <<< "$line" || fail "an App: bind bypasses koompi-launch: $line"
done < <(grep 'description = "App:' "$KEYBINDS")

(( failed == 0 )) || exit 1
echo "koompi-launch: argv, field codes, Path=, Terminal=, fallback and call sites hold"
