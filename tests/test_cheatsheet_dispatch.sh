#!/usr/bin/env bash
# The cheatsheet's run-a-bind path (OMARCHY-AUDIT O13), driven for real without
# touching the session: the Lua bind recorder replays a fixture config, and a
# Quickshell process loads HyprlandKeybinds against a `hyprctl` shim that prints
# fixture binds and logs every dispatch instead of running it.
#
# Under a Lua config `hyprctl binds` reports every bind as dispatcher `__lua`
# and `hyprctl dispatch` accepts only a Lua expression, so a bind is run by
# replaying the expression it was declared with; a classic config keeps the
# classic `hyprctl dispatch <dispatcher> <arg>` form. Both are asserted here.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
CHEATSHEET="$SHELL_ROOT/modules/koompi/cheatsheet"
RECORDER="$SHELL_ROOT/services/hyprlandKeybinds/recorder.lua"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

[[ -f "$RECORDER" ]] || fail "missing services/hyprlandKeybinds/recorder.lua"
grep -q 'property string configDir' "$SHELL_ROOT/services/HyprlandKeybinds.qml" \
    || fail "HyprlandKeybinds.configDir is no longer a property"
grep -q 'Quickshell.env("HYPRLAND_CONFIG")' "$SHELL_ROOT/services/HyprlandKeybinds.qml" \
    || fail "HyprlandKeybinds no longer honours HYPRLAND_CONFIG, which the probe below relies on"

# /usr/bin/qmllint is Qt 5 and rejects list<var> and pragma ComponentBehavior
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    LINT="$(mktemp -d)"
    ln -s "$SHELL_ROOT" "$LINT/qs"
    linted=0
    for f in "$CHEATSHEET"/*.qml "$SHELL_ROOT/services/HyprlandKeybinds.qml"; do
        out="$("$QMLLINT" -I "$LINT" -I /usr/lib/qt6/qml "$f" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects ${f#"$SHELL_ROOT"/}"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in ${f#"$SHELL_ROOT"/}"; }
        linted=$((linted + 1))
    done
    rm -rf "$LINT"
    echo "ok   qmllint: $linted cheatsheet files and HyprlandKeybinds.qml parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

# lua is a dependency of the hyprland package; a machine without it has no Lua config to read.
if ! command -v lua > /dev/null 2>&1; then
    echo "skip: lua not installed, recorder and probe not run"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/hypr/hyprland" "$WORK/hypr/custom" "$WORK/bin" "$WORK/shell" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache"

# The shapes keybinds.lua uses: a local wrapper around exec_cmd, a global, a
# namespaced dispatcher with a table argument, a closure, a mouse drag, a submap.
cat > "$WORK/hypr/hyprland/keybinds.lua" <<'LUA'
local function app(id, cmd)
    return hl.dsp.exec_cmd("koompi-launch --id " .. id .. " " .. cmd)
end
hl.env("qsConfig", "koompi")
hl.exec_cmd("must-not-run")
hl.bind("SUPER + W", app("brave", "brave"), { description = "App: Brave browser" })
hl.bind("SUPER + ALT + code:10", hl.dsp.global("quickshell:workspaceOne"), { description = "Workspace: One" })
hl.bind("SUPER + SHIFT + Right", hl.dsp.window.move({ direction = "r" }), { description = "Window: Move right" })
hl.bind("SUPER + Equal", function() end, { repeating = true, description = "Screen: Zoom in" })
hl.bind("SUPER + mouse:272", hl.dsp.window.drag(), { mouse = true, description = "Window: Move" })
hl.bind("SUPER + Q", hl.dsp.window.close()) -- hidden
hl.define_submap("vm", function()
    hl.bind("SUPER + ALT + F1", hl.dsp.submap("reset"), { description = "Shell: Leave VM mode" })
end)
LUA
cat > "$WORK/hypr/custom/keybinds.lua" <<'LUA'
hl.bind("SUPER + K", hl.dsp.exec_cmd("kiri voice", { float = true }), { description = "Kiri: Voice" })
LUA
printf '-- entry file; the recorder loads bind modules, not this\n' > "$WORK/hypr/hyprland.lua"

# hyprland.keybinds_notifications does not exist in the fixture: skipped, like hyprland.lua would.
rec="$(lua "$RECORDER" "$WORK/hypr" hyprland.keybinds hyprland.keybinds_notifications custom.keybinds 2> "$WORK/rec.err")"
rc=$?
(( rc == 0 )) || { cat "$WORK/rec.err" >&2; fail "recorder exited $rc on a good config"; }
[[ -s "$WORK/rec.err" ]] && { cat "$WORK/rec.err" >&2; fail "recorder wrote to stderr on a good config"; }
expect() {
    grep -qF -- "$2" <<< "$rec" || { echo "$rec" >&2; fail "recorder: $1"; }
}
expect "exec through a local wrapper" '"modmask":64,"key":"W","submap":"","description":"App: Brave browser","expr":"hl.dsp.exec_cmd(\"koompi-launch --id brave brave\")"'
expect "modifiers folded into modmask, key is the last token" '"modmask":72,"key":"code:10","submap":"","description":"Workspace: One","expr":"hl.dsp.global(\"quickshell:workspaceOne\")"'
expect "table argument serialised as Lua" '"modmask":65,"key":"Right","submap":"","description":"Window: Move right","expr":"hl.dsp.window.move({ direction = \"r\" })"'
expect "a closure has no expression" '"description":"Screen: Zoom in","expr":null'
expect "a mouse bind has no expression" '"key":"mouse:272","submap":"","description":"Window: Move","expr":null'
expect "an undescribed bind is still recorded" '"key":"Q","submap":"","description":"","expr":"hl.dsp.window.close()"'
expect "a submap bind carries its submap" '"submap":"vm","description":"Shell: Leave VM mode","expr":"hl.dsp.submap(\"reset\")"'
expect "custom.keybinds is loaded, second argument kept" '"key":"K","submap":"","description":"Kiri: Voice","expr":"hl.dsp.exec_cmd(\"kiri voice\", { float = true })"'
count="$(grep -c '"modmask"' <<< "$rec")"
(( count == 8 )) || fail "recorder emitted $count records, expected 8"
echo "ok   recorder: 8 fixture binds recorded with the expressions they were declared with"

# A module that throws: named on stderr, exit 1, and the binds before it still come out.
printf 'hl.bind("SUPER + Z", hl.dsp.global("quickshell:z"), { description = "Shell: Z" })\nerror("boom")\n' > "$WORK/hypr/custom/broken.lua"
rec="$(lua "$RECORDER" "$WORK/hypr" custom.broken 2> "$WORK/rec.err")"
rc=$?
(( rc == 1 )) || fail "recorder exited $rc on a broken module, expected 1"
grep -q 'custom.broken: .*boom' "$WORK/rec.err" || { cat "$WORK/rec.err" >&2; fail "recorder did not name the broken module"; }
grep -qF '"description":"Shell: Z"' <<< "$rec" || fail "recorder dropped the binds declared before the error"
echo "ok   recorder: a broken module is reported and the rest is kept"

# A wrong config directory must not look like a config with no binds.
lua "$RECORDER" "$WORK/nowhere" hyprland.keybinds > /dev/null 2> "$WORK/rec.err"
rc=$?
(( rc == 1 )) || fail "recorder exited $rc with no module present, expected 1"
grep -q 'none of the bind modules exist under' "$WORK/rec.err" || { cat "$WORK/rec.err" >&2; fail "recorder is silent when no module exists"; }
echo "ok   recorder: a directory with no bind module is an error, not an empty config"

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, recorder checked only"
    exit 0
fi

# symlinks, the real tree carries the assets
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

# Three classic records, one catchall, and the Lua records the fixture above
# produces (a stale one at the end that the source no longer declares).
cat > "$WORK/binds.txt" <<'TXT'
bindd
	modmask: 64
	submap: 
	key: T
	keycode: 0
	catchall: false
	description: App: Terminal
	dispatcher: exec
	arg: kitty

bindd
	modmask: 64
	submap: 
	key: 3
	keycode: 0
	catchall: false
	description: Workspace: Focus 3
	dispatcher: workspace
	arg: 3

bindd
	modmask: 64
	submap: 
	key: Slash
	keycode: 0
	catchall: false
	description: Shell: Toggle cheatsheet
	dispatcher: global
	arg: quickshell:cheatsheetToggle

bind
	modmask: 0
	submap: resize
	key: 
	keycode: 0
	catchall: true
	description: 
	dispatcher: submap
	arg: reset

bindd
	modmask: 64
	submap: 
	key: W
	keycode: 0
	catchall: false
	description: App: Brave browser
	dispatcher: __lua
	arg: 12

bindd
	modmask: 72
	submap: 
	key: SUPER + ALT + code:10
	keycode: 10
	catchall: false
	description: Workspace: One
	dispatcher: __lua
	arg: 14

bindd
	modmask: 65
	submap: 
	key: Right
	keycode: 0
	catchall: false
	description: Window: Move right
	dispatcher: __lua
	arg: 16

binded
	modmask: 64
	submap: 
	key: Equal
	keycode: 0
	catchall: false
	description: Screen: Zoom in
	dispatcher: __lua
	arg: 18

bindd
	modmask: 64
	submap: 
	key: mouse:272
	keycode: 0
	catchall: false
	description: Window: Move
	dispatcher: __lua
	arg: 20

bindd
	modmask: 72
	submap: vm
	key: F1
	keycode: 0
	catchall: false
	description: Shell: Leave VM mode
	dispatcher: __lua
	arg: 22

bindd
	modmask: 64
	submap: 
	key: K
	keycode: 0
	catchall: false
	description: Kiri: Voice
	dispatcher: __lua
	arg: 24

bindd
	modmask: 64
	submap: 
	key: Z
	keycode: 0
	catchall: false
	description: Shell: Not in the source
	dispatcher: __lua
	arg: 26
TXT

cat > "$WORK/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
if [[ "${1:-}" == binds ]]; then cat "$SHIM_BINDS"; exit 0; fi
{ printf '%s' "$1"; shift; printf '\t%s' "$@"; printf '\n'; } >> "$SHIM_LOG"
exit 0
SH
chmod +x "$WORK/bin/hyprctl"
: > "$WORK/shim.log"

cat > "$WORK/shell/cheatsheet_probe.qml" <<'QML'
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: probe
    property string shimLog: Quickshell.env("SHIM_LOG")
    property int failures: 0

    function check(label, ok, detail) {
        console.log((ok ? "PASS " : "FAIL ") + label + (detail ? "  " + detail : ""));
        if (!ok) probe.failures++;
    }
    function find(description) {
        return HyprlandKeybinds.keybinds.find(b => b.description === description) ?? null;
    }
    function argv(bind) { return JSON.stringify(HyprlandKeybinds.dispatchArgv(bind)); }
    function same(a, b) { return JSON.stringify(a) === JSON.stringify(b); }

    Component { id: fileReader; FileView { blockLoading: true } }

    Timer {
        id: settle
        property int ticks: 0
        interval: 200
        repeat: true
        running: true
        onTriggered: {
            ticks++;
            const ready = HyprlandKeybinds.keybinds.length > 0
                && Object.keys(HyprlandKeybinds.recorded).length > 0;
            if (!ready && ticks < 50) return;
            settle.stop();
            probe.run(ready);
        }
    }

    function run(ready) {
        probe.check("hyprctl binds and the recorder both answered", ready,
            "binds=" + HyprlandKeybinds.keybinds.length + " recorded=" + Object.keys(HyprlandKeybinds.recorded).length);
        probe.check("12 binds parsed", HyprlandKeybinds.keybinds.length === 12, "" + HyprlandKeybinds.keybinds.length);

        const terminal = probe.find("App: Terminal");
        const workspace = probe.find("Workspace: Focus 3");
        const global = probe.find("Shell: Toggle cheatsheet");
        const catchall = HyprlandKeybinds.keybinds.find(b => b.catchall) ?? null;
        probe.check("classic exec is dispatchable as hyprctl dispatch exec <arg>",
            HyprlandKeybinds.dispatchable(terminal) && probe.same(HyprlandKeybinds.dispatchArgv(terminal), ["hyprctl", "dispatch", "exec", "kitty"]), probe.argv(terminal));
        probe.check("classic workspace builds hyprctl dispatch workspace 3",
            probe.same(HyprlandKeybinds.dispatchArgv(workspace), ["hyprctl", "dispatch", "workspace", "3"]), probe.argv(workspace));
        probe.check("classic global builds hyprctl dispatch global <name>",
            probe.same(HyprlandKeybinds.dispatchArgv(global), ["hyprctl", "dispatch", "global", "quickshell:cheatsheetToggle"]), probe.argv(global));
        probe.check("a catchall submap row is not dispatchable",
            catchall !== null && !HyprlandKeybinds.dispatchable(catchall) && HyprlandKeybinds.dispatchArgv(catchall).length === 0, "");

        const brave = probe.find("App: Brave browser");
        const codeChord = probe.find("Workspace: One");
        const move = probe.find("Window: Move right");
        const voice = probe.find("Kiri: Voice");
        probe.check("a Lua exec bind replays the exec_cmd it was declared with, unwrapped",
            probe.same(HyprlandKeybinds.dispatchArgv(brave), ["hyprctl", "dispatch", 'hl.dsp.exec_cmd("koompi-launch --id brave brave")']), probe.argv(brave));
        probe.check("a Lua global bind with a keycode chord matches on the last token",
            probe.same(HyprlandKeybinds.dispatchArgv(codeChord), ["hyprctl", "dispatch", 'hl.dsp.global("quickshell:workspaceOne")']), probe.argv(codeChord));
        probe.check("a namespaced dispatcher keeps its table argument",
            probe.same(HyprlandKeybinds.dispatchArgv(move), ["hyprctl", "dispatch", 'hl.dsp.window.move({ direction = "r" })']), probe.argv(move));
        probe.check("custom.keybinds binds are recovered too",
            probe.same(HyprlandKeybinds.dispatchArgv(voice), ["hyprctl", "dispatch", 'hl.dsp.exec_cmd("kiri voice", { float = true })']), probe.argv(voice));

        const closure = probe.find("Screen: Zoom in");
        const drag = probe.find("Window: Move");
        const submap = probe.find("Shell: Leave VM mode");
        const stale = probe.find("Shell: Not in the source");
        probe.check("a Lua closure is not dispatchable", closure !== null && !HyprlandKeybinds.dispatchable(closure), "expr=" + JSON.stringify(closure?.expr));
        probe.check("a mouse drag is not dispatchable", drag !== null && !HyprlandKeybinds.dispatchable(drag), "expr=" + JSON.stringify(drag?.expr));
        probe.check("a submap bind is not dispatchable", submap !== null && !HyprlandKeybinds.dispatchable(submap), "");
        probe.check("a bind the source no longer declares is not dispatchable", stale !== null && !HyprlandKeybinds.dispatchable(stale), "expr=" + JSON.stringify(stale?.expr));

        probe.check("searchText carries chord, key and description",
            HyprlandKeybinds.searchText(codeChord) === "Super Alt code:10 Workspace: One", HyprlandKeybinds.searchText(codeChord));
        probe.check("modifiersOf follows the user-facing order",
            probe.same(HyprlandKeybinds.modifiersOf(13), ["Ctrl", "Shift", "Alt"]), JSON.stringify(HyprlandKeybinds.modifiersOf(13)));
        probe.check("keybindCategories come from the merged list",
            HyprlandKeybinds.keybindCategories.includes("Kiri") && HyprlandKeybinds.keybindCategories.includes("App"), JSON.stringify(HyprlandKeybinds.keybindCategories));

        probe.check("dispatch returns true for a runnable bind and false otherwise",
            HyprlandKeybinds.dispatch(terminal) === true && HyprlandKeybinds.dispatch(brave) === true
                && HyprlandKeybinds.dispatch(closure) === false && HyprlandKeybinds.dispatch(catchall) === false, "");
        flush.start();
    }

    Timer {
        id: flush
        interval: 500
        onTriggered: {
            const view = fileReader.createObject(probe, { path: probe.shimLog });
            // execDetached spawns concurrently, so the order the shim logs is not fixed
            const lines = view.text().split("\n").filter(l => l.length > 0).sort();
            view.destroy();
            probe.check("the shim saw exactly the two runnable dispatches, argv intact",
                probe.same(lines, ["dispatch\texec\tkitty", 'dispatch\thl.dsp.exec_cmd("koompi-launch --id brave brave")']),
                JSON.stringify(lines));
            console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
            Qt.callLater(() => Qt.quit());
        }
    }
}
QML

out="$(cd "$WORK" && PATH="$WORK/bin:$PATH" SHIM_BINDS="$WORK/binds.txt" SHIM_LOG="$WORK/shim.log" \
    HYPRLAND_CONFIG="$WORK/hypr/hyprland.lua" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 120 qs -p "$WORK/shell/cheatsheet_probe.qml" 2>&1)"
echo "$out" | sed -n 's/.*qml\x1b\[0m: //p;s/^ DEBUG qml: //p' | grep -E '^(PASS|FAIL|PROBE)' || true

if ! grep -q "PROBE OK" <<< "$out"; then
    echo "--- probe output ---" >&2
    echo "$out" >&2
    exit 1
fi
echo "ok: HyprlandKeybinds merges hyprctl binds with the recorded Lua declarations and dispatches through hyprctl"
