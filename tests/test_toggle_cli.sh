#!/usr/bin/env bash
# koompi-toggle is one bash case table in front of three IPC targets, and the
# thing scripts branch on is its exit code (OMARCHY-AUDIT O24). qs is a PATH
# shim here that logs its argv and plays a shell whose switch is on, off,
# missing, or too old to know the target, so every cell of the table (three
# switches x four verbs) is driven without an IPC call reaching the session.
# The notification chords (O12) are three files wide, keybinds_shell_extra.lua
# -> hyprland.lua -> Notifications.qml, so their names are pinned to each other
# the way test_sidebar_drawer_binds.sh pins the drawer binds.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
TOOL="$REPO_ROOT/dots/.local/bin/koompi-toggle"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SERVICES="$SHELL_ROOT/services"
HYPR="$REPO_ROOT/dots/.config/hypr"
BINDS="$HYPR/hyprland/keybinds_shell_extra.lua"

failed=0
fail() { printf 'FAIL: %s\n' "$1" >&2; failed=1; }
[[ -x "$TOOL" ]] || { echo "FAIL: $TOOL is not executable" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
export QS_SHIM_LOG="$WORK/qs.log" QS_SHIM_STATE="$WORK/state" QS_SHIM_MODE=live

# The shim. Whatever the target, the verb is the last argument; nightlight's
# functions are the verbs themselves and the other two take it as a parameter.
cat > "$WORK/bin/qs" <<'SHIM'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$QS_SHIM_LOG"
case "$QS_SHIM_MODE" in
    dead) echo 'No running instances for "/x/koompi/shell.qml"' >&2; exit 255 ;;
    old)  echo "Target not found."; exit 0 ;;
esac
state="$(cat "$QS_SHIM_STATE")"
case "${@: -1}" in
    on) state=on ;;
    off) state=off ;;
    toggle) [[ "$state" == on ]] && state=off || state=on ;;
    status) ;;
    *) echo "usage: on|off|toggle|status"; exit 0 ;;
esac
printf '%s' "$state" > "$QS_SHIM_STATE"
echo "$state"
SHIM
chmod +x "$WORK/bin/qs"
PATH="$WORK/bin:$PATH"

# run <expected rc> <expected stdout> <expected qs argv> -- <koompi-toggle args>
run() {
    local want_rc="$1" want_out="$2" want_argv="$3"; shift 4
    : > "$QS_SHIM_LOG"
    local out rc
    out="$("$TOOL" "$@" 2>"$WORK/err")"; rc=$?
    local label="koompi-toggle $*"
    (( rc == want_rc )) || fail "$label: exit $rc, want $want_rc ($(cat "$WORK/err"))"
    [[ "$out" == "$want_out" ]] || fail "$label: stdout '$out', want '$want_out'"
    local argv=""; [[ -s "$QS_SHIM_LOG" ]] && argv="$(cat "$QS_SHIM_LOG")"
    [[ "$argv" == "$want_argv" ]] || fail "$label: qs called with '$argv', want '$want_argv'"
}
ipc="-c koompi ipc --any-display call"
declare -A target=([keep-awake]="idle inhibit" [night-light]="nightlight" [silent]="notifications silent")

# Three switches x four verbs, from off: on -> on, toggle -> off, status is 1,
# off stays off, status is 1; then on and status is 0. Bare = toggle.
for thing in keep-awake night-light silent; do
    t="${target[$thing]}"
    printf off > "$QS_SHIM_STATE"
    run 0 on  "$ipc $t on"     -- "$thing" on
    run 1 off "$ipc $t toggle" -- "$thing" toggle
    run 1 off "$ipc $t status" -- "$thing" status
    run 1 off "$ipc $t off"    -- "$thing" off
    run 0 on  "$ipc $t toggle" -- "$thing"
    run 0 on  "$ipc $t status" -- "$thing" status
done

# No shell: 2, nothing printed, whatever the verb.
QS_SHIM_MODE=dead
printf off > "$QS_SHIM_STATE"
run 2 "" "$ipc nightlight status"       -- night-light status
run 2 "" "$ipc idle inhibit toggle"     -- keep-awake
run 2 "" "$ipc notifications silent on" -- silent on
# A shell without the handlers answers "Target not found." with exit 0: still 2.
QS_SHIM_MODE=old
run 2 "" "$ipc notifications silent status" -- silent status
QS_SHIM_MODE=live

# Bad arguments never reach qs: usage on stderr, 64.
for args in "" "screensaver" "silent maybe" "silent on extra" "keep_awake status"; do
    # shellcheck disable=SC2086  # the args are the test's own words
    run 64 "" "" -- $args
    grep -q '^Usage: koompi-toggle' "$WORK/err" || fail "koompi-toggle $args: no usage on stderr"
done
out="$("$TOOL" --help)"; rc=$?
if (( rc != 0 )) || ! grep -q 'keep-awake|night-light|silent' <<< "$out"; then fail "--help is not exit 0 with usage"; fi
echo "ok   koompi-toggle: 3 switches x 4 verbs, exit 0/1/2/64 as documented"

# The chords: four binds, each described (the cheatsheet is built from the
# description), each naming an IPC function Notifications.qml defines; the
# loader requires the file right after keybinds.lua.
count="$(grep -c '^hl.bind(.*notifications \.\. ' "$BINDS")"
(( count == 4 )) || fail "expected 4 notification hl.bind( in keybinds_shell_extra.lua, found $count"
(( $(grep -c 'description = "Shell: Notifications - ' "$BINDS") == 4 )) || fail "not every notification bind has a description"
while read -r fn; do
    grep -q "function $fn(): string" "$SERVICES/Notifications.qml" \
        || fail "keybinds_shell_extra.lua calls notifications $fn but Notifications.qml has no such IPC function"
done < <(grep -oE 'notifications \.\. " [a-zA-Z]+"' "$BINDS" | awk '{print $4}' | tr -d '"' | sort -u)
grep -A2 'require("hyprland.keybinds")' "$HYPR/hyprland.lua" | grep -q 'require("hyprland.keybinds_shell_extra")' \
    || fail "hyprland.lua does not require hyprland.keybinds_shell_extra right after hyprland.keybinds"
grep -qE '\+ Comma"' "$HYPR/hyprland/keybinds.lua" && fail "keybinds.lua now binds Comma too; the notification chords collide"
for f in "$BINDS" "$HYPR/hyprland.lua"; do
    if command -v luac >/dev/null 2>&1; then
        luac -p "$f" || fail "luac -p rejects ${f#"$REPO_ROOT"/}"
    else
        echo "skip: no luac, ${f#"$REPO_ROOT"/} not parsed"
    fi
done
echo "ok   chords: 4 notification binds described, IPC names match Notifications.qml, loader order right"

# The IPC handlers themselves: target names koompi-toggle calls, and a status
# that returns the literal on/off, as the tool's case table expects.
for pair in "Idle:idle" "Hyprsunset:nightlight" "Notifications:notifications"; do
    grep -q "target: \"${pair#*:}\"" "$SERVICES/${pair%%:*}.qml" \
        || fail "services/${pair%%:*}.qml has no IpcHandler with target \"${pair#*:}\""
done
grep -q 'function inhibit(verb: string): string' "$SERVICES/Idle.qml" || fail "Idle.qml: no inhibit(verb) IPC function"
grep -q 'function status(): string' "$SERVICES/Hyprsunset.qml" || fail "Hyprsunset.qml: no status() IPC function"
grep -q 'function silent(verb: string): string' "$SERVICES/Notifications.qml" || fail "Notifications.qml: no silent(verb) IPC function"

# /usr/bin/qmllint is Qt 5 and rejects list<var> and pragma ComponentBehavior
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    ln -s "$SHELL_ROOT" "$WORK/qs"
    for f in Idle Hyprsunset Notifications; do
        out="$("$QMLLINT" -I "$WORK" -I /usr/lib/qt6/qml "$SERVICES/$f.qml" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects services/$f.qml"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in services/$f.qml"; }
    done
    echo "ok   qmllint: Idle, Hyprsunset, Notifications parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

(( failed == 0 )) || exit 1
echo "toggle cli: all checks passed"
