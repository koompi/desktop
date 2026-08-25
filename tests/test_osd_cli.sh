#!/usr/bin/env bash
# koompi-osd is one qs IPC call behind an argument table and koompi-launch-tui
# one koompi-launch call behind a terminal table (OMARCHY-AUDIT O23, O29). qs,
# koompi-launch and the terminals are PATH shims that log their argv, so every
# row of both tables and every exit code is driven without touching the session.
# The rest pins the pieces to each other: the osd IpcHandler and OsdMessage in
# the shell, the TUI. rules and launch_sysmon.sh, the battery hook events in
# Battery.qml, koompi-hook's usage and docs/agents/hooks.md, the cli's osd row.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
BIN="$REPO_ROOT/dots/.local/bin"
OSD="$BIN/koompi-osd"
TUI="$BIN/koompi-launch-tui"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
OSD_DIR="$SHELL_ROOT/modules/koompi/onScreenDisplay"
HYPR="$REPO_ROOT/dots/.config/hypr/hyprland"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }
for t in "$OSD" "$TUI"; do [[ -x "$t" ]] || { echo "FAIL: $t is not executable" >&2; exit 1; }; done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
export SHIM_LOG="$WORK/argv.log" QS_SHIM_MODE=live
mkdir -p "$WORK/bin" "$WORK/foot-only" "$WORK/no-terminal"
cat > "$WORK/bin/qs" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$SHIM_LOG"
case "$QS_SHIM_MODE" in
    dead) echo 'No running instances for "/x/koompi/shell.qml"' >&2; exit 255 ;;
    old)  echo "Target not found."; exit 0 ;;
    arity) echo "ipc: The following arguments were not expected: $*" >&2; exit 109 ;;
esac
echo ok
SHIM
# koompi-launch and the terminals only record what they were handed
# shellcheck disable=SC2016  # the shim's $0 $* expand when the shim runs
for shim in koompi-launch wezterm foot; do
    printf '#!/usr/bin/env bash\nprintf "%%s\\n" "$0 $*" >> "$SHIM_LOG"\n' > "$WORK/bin/$shim"
done
chmod +x "$WORK/bin/"*
cp "$WORK/bin/koompi-launch" "$WORK/bin/foot" "$WORK/foot-only/"
cp "$WORK/bin/koompi-launch" "$WORK/no-terminal/"
PATH="$WORK/bin:$PATH"
BASH_BIN="$(command -v bash)"
ln -s "$BASH_BIN" "$WORK/foot-only/bash"; ln -s "$BASH_BIN" "$WORK/no-terminal/bash"  # the tool's shebang

# run <tool> <expected rc> <expected argv line> -- <args>; TOOL_PATH narrows the
# PATH the tool itself sees
run() {
    local tool="$1" want_rc="$2" want_argv="$3"; shift 4
    : > "$SHIM_LOG"
    local rc label
    PATH="${TOOL_PATH:-$PATH}" "$BASH_BIN" "$tool" "$@" >"$WORK/out" 2>"$WORK/err"; rc=$?
    label="${tool##*/} $*"
    (( rc == want_rc )) || fail "$label: exit $rc, want $want_rc ($(cat "$WORK/err"))"
    local argv=""; [[ -s "$SHIM_LOG" ]] && argv="$(cat "$SHIM_LOG")"
    [[ "$argv" == "$want_argv" ]] || fail "$label: shim called with '$argv', want '$want_argv'"
}
usage_on_stderr() { grep -q "^Usage: $1" "$WORK/err" || fail "$1 $2: no usage on stderr"; }

# --- koompi-osd: the four options in every spelling, defaults -1 and 0, `--` before
# the values so a message can start with a dash; no instance (qs 255), an older
# shell ("Target not found.") and a shell without the handler (qs 109) are all 2.
ipc="-c koompi ipc --any-display call osd show --"
run "$OSD" 0 "$ipc check hello 40 0"                -- -i check -m hello -p 40
run "$OSD" 0 "$ipc  hello -1 0"                     -- -m hello
run "$OSD" 0 "$ipc check  -1 0"                     -- -i check
run "$OSD" 0 "$ipc check -dashed 100 2500"          -- --icon check --message -dashed --progress 100 --duration 2500
run "$OSD" 0 "$ipc battery_alert Low battery 0 0"   -- -p 0 -m "Low battery" -i battery_alert
[[ -s "$WORK/out" ]] && fail "koompi-osd printed '$(cat "$WORK/out")' on success"
QS_SHIM_MODE=dead; run "$OSD" 2 "$ipc check hello -1 0" -- -i check -m hello
grep -q 'shell is not running' "$WORK/err" || fail "dead shell: no message on stderr"
QS_SHIM_MODE=old;  run "$OSD" 2 "$ipc check hello -1 0" -- -i check -m hello
grep -q 'shell older than this tool' "$WORK/err" || fail "old shell: no hint on stderr"
QS_SHIM_MODE=arity; run "$OSD" 2 "$ipc check hello -1 0" -- -i check -m hello
grep -q 'shell older than this tool' "$WORK/err" || fail "shell without the handler: no hint on stderr"
QS_SHIM_MODE=live
for args in "" "-p 40" "-i" "-m hello -p 101" "-m hello -p -5" "-m hello -p x" "-m hello -d 0" "-m hello -d 1.5" "-m hello --loud" "-x"; do
    # shellcheck disable=SC2086  # the args are the test's own words
    run "$OSD" 64 "" -- $args
    usage_on_stderr koompi-osd "$args"
done
if ! "$OSD" --help > "$WORK/out" 2>&1 || ! grep -q '^Usage: koompi-osd' "$WORK/out"; then fail "koompi-osd --help is not exit 0 with usage"; fi
echo "ok   koompi-osd: argument table, exit 0/2/64, -- before the values"

# --- koompi-launch-tui: class TUI.<app-id>, the first terminal from variables.lua's
# order, the command after koompi-launch's --, bad args never reach koompi-launch.
run "$TUI" 0 "$WORK/bin/koompi-launch --id sysmon-scratch -- wezterm start --class TUI.sysmon-scratch -- sh -c btop || htop || top" \
    -- sysmon-scratch sh -c 'btop || htop || top'
run "$TUI" 0 "$WORK/bin/koompi-launch --id lazygit -- wezterm start --class TUI.lazygit -- lazygit" -- lazygit lazygit
TOOL_PATH="$WORK/foot-only" run "$TUI" 0 "$WORK/foot-only/koompi-launch --id btop -- foot --app-id TUI.btop -- btop" -- btop btop
TOOL_PATH="$WORK/no-terminal" run "$TUI" 69 "" -- btop btop
for args in "" "btop" "bad/id btop" "-btop btop"; do
    # shellcheck disable=SC2086
    run "$TUI" 64 "" -- $args
done
if ! "$TUI" --help > "$WORK/out" 2>&1 || ! grep -q '^Usage: koompi-launch-tui' "$WORK/out"; then fail "koompi-launch-tui --help is not exit 0 with usage"; fi
grep -q "for t in wezterm foot kitty alacritty" "$TUI" || fail "koompi-launch-tui's terminal order is not wezterm foot kitty alacritty"
grep -q "'wezterm' 'foot' 'kitty -1' 'alacritty'" "$HYPR/variables.lua" || fail "variables.lua terminal order changed; update koompi-launch-tui to match"
echo "ok   koompi-launch-tui: TUI.<app-id> class, terminal order, exit 0/64/69"

# --- the pieces the tools rely on
grep -q 'target: "osd"' "$OSD_DIR/OnScreenDisplay.qml" || fail "OnScreenDisplay.qml has no IpcHandler with target \"osd\""
grep -q 'function show(icon: string, message: string, progress: int, duration: int): string' "$OSD_DIR/OnScreenDisplay.qml" \
    || fail "OnScreenDisplay.qml: no show(icon, message, progress, duration) IPC function"
grep -q 'sourceComponent: OsdMessage' "$OSD_DIR/OnScreenDisplay.qml" || fail "OnScreenDisplay.qml does not render OsdMessage"
[[ -f "$OSD_DIR/indicators/OsdMessage.qml" ]] || fail "indicators/OsdMessage.qml missing"
grep -c 'PanelWindow' "$OSD_DIR/OnScreenDisplay.qml" | grep -qx 1 || fail "the OSD grew a second window"

grep -q 'exec koompi-launch-tui sysmon-scratch ' "$HYPR/scripts/launch_sysmon.sh" || fail "launch_sysmon.sh does not go through koompi-launch-tui"
grep -q 'class = "^TUI\\\\." }, *float = true' "$HYPR/rules.lua" || fail "rules.lua has no float rule for ^TUI\\. classes"
grep -q 'class = "^(TUI\\\\.sysmon-scratch)$" }, *workspace = "special:sysmon silent"' "$HYPR/rules.lua" \
    || fail "rules.lua no longer pins TUI.sysmon-scratch to special:sysmon"
grep -q '"sysmon-scratch)$"' "$HYPR/rules.lua" && fail "rules.lua still matches the bare sysmon-scratch class, which koompi-launch-tui never sets"
grep -q "sysmon 'sysmon-scratch' koompi-launch" "$HYPR/keybinds.lua" || fail "keybinds.lua's sysmon bind no longer greps for sysmon-scratch"
if command -v luac >/dev/null 2>&1; then
    luac -p "$HYPR/rules.lua" || fail "luac -p rejects hyprland/rules.lua"
else
    echo "skip: no luac, rules.lua not parsed"
fi

for event in battery-low battery-critical; do
    grep -q "fireHook(\"$event\")" "$SHELL_ROOT/services/Battery.qml" || fail "Battery.qml does not fire $event"
    grep -q "^  $event " "$BIN/koompi-hook" || fail "koompi-hook usage does not list $event"
    grep -q "^- \`$event\`" "$REPO_ROOT/docs/agents/hooks.md" || fail "docs/agents/hooks.md has no row for $event"
done
grep -q '"koompi-hook", event, "--"' "$SHELL_ROOT/services/Battery.qml" || fail "Battery.qml's fireHook does not call koompi-hook <event> --"
grep -q '.name = "osd", .helper = "koompi-osd"' "$REPO_ROOT/cli/src/main.zig" || fail "cli/src/main.zig has no osd row"
echo "ok   wiring: IPC target, TUI rules, sysmon scratch, battery hook events, cli row"

# /usr/bin/qmllint is Qt 5 and rejects list<var> and pragma ComponentBehavior
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    ln -s "$SHELL_ROOT" "$WORK/qs"
    for f in OnScreenDisplay indicators/OsdMessage ../../../services/Battery; do
        out="$("$QMLLINT" -I "$WORK" -I /usr/lib/qt6/qml "$OSD_DIR/$f.qml" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects $f.qml"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in $f.qml"; }
    done
    echo "ok   qmllint: OnScreenDisplay, OsdMessage, Battery parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

(( failed == 0 )) || exit 1
echo "osd cli: all checks passed"
