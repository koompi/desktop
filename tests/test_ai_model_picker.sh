#!/usr/bin/env bash
# J45: the model is switched inside the sidebar. The composer chip and the
# status-bar name open ModelPicker.qml instead of the Settings window, the
# no-key button puts `/key ` in the composer, `/key` takes the whole line and
# `/model` alone opens the picker. The static half reads the sources; the probe
# half loads ModelPicker.qml with `qs -p`, three fake models and no Ai singleton,
# opens it and drives the highlight and the pick the way the keys and a click do.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SIDEBAR="$SHELL_ROOT/modules/koompi/sidebarLeft"
COMPOSER="$SIDEBAR/aiChat/ChatComposer.qml"
STATUSBAR="$SIDEBAR/aiChat/composer/ChatStatusBar.qml"
PICKER="$SIDEBAR/aiChat/composer/ModelPicker.qml"
COMMANDS="$SIDEBAR/aiChat/ChatCommands.qml"
TRANSCRIPT="$SIDEBAR/aiChat/ChatTranscript.qml"
AICHAT="$SIDEBAR/AiChat.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for f in "$COMPOSER" "$STATUSBAR" "$PICKER" "$COMMANDS" "$TRANSCRIPT" "$AICHAT"; do
    [[ -f "$f" ]] || fail "missing $f"
done

# The two entry points open the picker; neither leaves the sidebar.
grep -q 'settingsRequested' "$COMPOSER" && fail "ChatComposer.qml still calls settingsRequested"
grep -q 'settingsRequested' "$STATUSBAR" && fail "ChatStatusBar.qml still calls settingsRequested"
grep -q 'onClickedAction: () => root.modelPickerShown = !root.modelPickerShown' "$COMPOSER" \
    || fail "the composer chip does not toggle modelPickerShown"
grep -q 'onClicked: root.modelPickerRequested()' "$STATUSBAR" \
    || fail "the status-bar model name does not request the picker"
grep -q 'Settings > AI' "$COMPOSER" && fail "ChatComposer.qml still points at Settings > AI"
grep -q 'Settings > AI' "$STATUSBAR" && fail "ChatStatusBar.qml still points at Settings > AI"
echo "ok   static: chip and status-bar name open the picker, neither names Settings > AI"

# No key: the button says so and puts /key in the composer.
grep -q 'buttonText: Translation.tr("Set key")' "$STATUSBAR" || fail "the no-key button is not labelled Set key"
grep -q 'onClicked: root.keyRequested()' "$STATUSBAR" || fail "the no-key button does not emit keyRequested"
grep -q 'needs an API key' "$STATUSBAR" || fail "the red needs-an-API-key text is gone"
grep -q 'onKeyRequested: composer.prefill(root.commandPrefix + "key ")' "$AICHAT" \
    || fail "AiChat.qml does not prefill /key on keyRequested"
echo "ok   static: no-key button reads Set key and prefills /key"

# /key takes the rest of the line; /model alone opens the picker; no moved notes.
key_block="$(sed -n '/name: "key",/,/^        },/p' "$COMMANDS")"
[[ -n "$key_block" ]] || fail "no /key command in ChatCommands.qml"
grep -q 'args\[0\]' <<< "$key_block" && fail "/key still reads args[0]"
grep -q 'args.join(" ").trim()' <<< "$key_block" || fail "/key does not take the rest of the line trimmed"
grep -q 'noteThatItMoved' <<< "$key_block" && fail "/key still says it moved to Settings"
model_block="$(sed -n '/name: "model",/,/^        },/p' "$COMMANDS")"
grep -q 'root.modelPickerRequested()' <<< "$model_block" || fail "/model with no argument does not open the picker"
grep -q 'Ai.setModel(modelId)' <<< "$model_block" || fail "/model with an argument no longer calls Ai.setModel"
grep -q 'noteThatItMoved' <<< "$model_block" && fail "/model still says it moved to Settings"
grep -q 'onModelPickerRequested: composer.modelPickerShown = true' "$AICHAT" \
    || fail "AiChat.qml does not open the picker on the command's request"
echo "ok   static: /key takes the whole line, /model alone opens the picker, moved notes gone"

# The picker is fed a list and answers with a signal; the composer does the Ai wiring.
grep -q 'property var models' "$PICKER" || fail "ModelPicker.qml has no models property"
grep -q 'signal picked(string id)' "$PICKER" || fail "ModelPicker.qml has no picked(string id) signal"
grep -q 'Ai\.' "$PICKER" && fail "ModelPicker.qml reaches for the Ai singleton"
grep -qE 'Qt\.Key_(Up|Down)' "$PICKER" && grep -q 'Qt.Key_Return' "$PICKER" && grep -q 'Qt.Key_Escape' "$PICKER" \
    || fail "ModelPicker.qml does not handle Up, Down, Enter and Escape"
grep -q 'Ai.setModel(id)' "$AICHAT" || fail "AiChat.qml does not wire picked to Ai.setModel"
# The owner sets onVisibleChanged on the instance, so the component must seed its
# highlight some other way or the instance handler silently replaces it.
grep -q '^    onVisibleChanged:' "$PICKER" && fail "ModelPicker.qml seeds through onVisibleChanged, which AiChat.qml overrides"
grep -q 'Accessible.role: Accessible.List$' "$PICKER" || fail "ModelPicker.qml root has no Accessible.role List"
grep -q 'Accessible.role: Accessible.ListItem' "$PICKER" || fail "ModelPicker.qml rows have no Accessible.role ListItem"
grep -q 'Accessible.selected: row.selected' "$PICKER" || fail "ModelPicker.qml rows do not report Accessible.selected"
grep -q 'onHoveredChanged' "$PICKER" && fail "ModelPicker.qml still selects from hovered, which the list scrolling under a resting pointer flips"
grep -q 'onPositionChanged: mouse => root.noteHover(row.index' "$PICKER" || fail "ModelPicker.qml rows do not select from pointer movement"
for f in "$COMPOSER" "$STATUSBAR" "$PICKER" "$COMMANDS" "$TRANSCRIPT" "$AICHAT"; do
    lines="$(wc -l < "$f")"
    (( lines <= 400 )) || fail "$(basename -- "$f") is $lines lines, cap is 400"
done
echo "ok   static: picker takes models, reports picked, knows no Ai, seeds without onVisibleChanged, has list roles; every touched file under 400 lines"

# /usr/bin/qmllint is Qt 5 and rejects list<var> and pragma ComponentBehavior
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    LINT="$(mktemp -d)"
    ln -s "$SHELL_ROOT" "$LINT/qs"
    for f in "$COMPOSER" "$STATUSBAR" "$PICKER" "$COMMANDS" "$TRANSCRIPT" "$AICHAT"; do
        out="$("$QMLLINT" -I "$LINT" -I /usr/lib/qt6/qml "$f" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects $(basename -- "$f")"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in $(basename -- "$f")"; }
    done
    rm -rf "$LINT"
    echo "ok   qmllint: the six touched files parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
# nothing in the probe should reach a keyring or a model server
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/ollama"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/secret-tool"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/model_picker_probe.qml" <<'QML'
import qs.modules.koompi.sidebarLeft.aiChat.composer
import Quickshell
import QtQuick

ShellRoot {
    id: probe
    property int failures: 0
    property var picks: []
    property int dismissals: 0

    function check(label, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "PASS " : "FAIL ") + label + "  got=" + JSON.stringify(got) + (ok ? "" : " want=" + JSON.stringify(want)));
        if (!ok) probe.failures++;
    }

    // twelve rows, the current one last: past maxHeight, so opening has to scroll
    property var many: Array.from({ length: 12 }, (_, i) => ({ id: "m" + i, name: "Model " + i, description: "" }))

    Item {
        width: 320
        height: 480
        ModelPicker {
            id: tall
            width: 320
            visible: false
            models: probe.many
            currentId: "m11"
            onVisibleChanged: if (visible) Qt.callLater(tall.focusFirst)
        }
        ModelPicker {
            id: picker
            width: 320
            visible: false
            // the same instance-level handler AiChat.qml sets; the seeding must survive it
            onVisibleChanged: if (visible) Qt.callLater(picker.focusFirst)
            models: [
                { id: "alpha", name: "Alpha", description: "first fake model" },
                { id: "beta", name: "Beta", description: "second fake model" },
                { id: "gamma", name: "Gamma", description: "" }
            ]
            currentId: "beta"
            onPicked: id => probe.picks.push(id)
            onDismissed: probe.dismissals++
        }
    }

    Timer {
        interval: 300; running: true; repeat: false
        onTriggered: {
            picker.visible = true;
            probe.check("open: three rows", picker.rowCount, 3);
            probe.check("open: row names", [0, 1, 2].map(i => picker.rowAt(i).modelData.name), ["Alpha", "Beta", "Gamma"]);
            probe.check("open: only the current row is marked", [0, 1, 2].map(i => picker.rowAt(i).isCurrent), [false, true, false]);
            probe.check("open: highlight starts on the current row", picker.selectedIndex, 1);
            probe.check("open: rows read as list items with the highlight selected", [0, 1, 2].map(i => picker.rowAt(i).Accessible.selected), [false, true, false]);
            probe.check("open: current row says so to a screen reader", picker.rowAt(1).Accessible.name, "Beta, current");
            probe.check("open: the sheet is a named list", [picker.Accessible.role === Accessible.List, picker.Accessible.name.length > 0], [true, true]);

            // what Down, Down, Enter do
            picker.moveSelection(1);
            probe.check("down: highlight moves to 2", picker.selectedIndex, 2);
            probe.check("down: Accessible.selected follows", [0, 1, 2].map(i => picker.rowAt(i).Accessible.selected), [false, false, true]);
            picker.moveSelection(1);
            probe.check("down: stops at the last row", picker.selectedIndex, 2);
            picker.activateSelected();
            probe.check("enter: picked carries the highlighted id", probe.picks, ["gamma"]);

            // what Up, Up, Up and a click do
            picker.moveSelection(-2);
            probe.check("up: highlight moves to 0", picker.selectedIndex, 0);
            picker.moveSelection(-1);
            probe.check("up: stops at the first row", picker.selectedIndex, 0);
            picker.rowAt(0).clicked();
            probe.check("click: picked carries the row's id", probe.picks, ["gamma", "alpha"]);

            // reopened after the owner switched: the mark and the highlight follow
            picker.visible = false;
            picker.currentId = "gamma";
            picker.visible = true;
            probe.check("reopen: mark follows currentId", [0, 1, 2].map(i => picker.rowAt(i).isCurrent), [false, false, true]);
            probe.check("reopen: highlight follows currentId", picker.selectedIndex, 2);
            probe.check("nothing dismissed it", probe.dismissals, 0);

            // hover selects on pointer movement only
            tall.visible = true;
            tall.noteHover(0, Qt.point(10, 10));
            probe.check("hover: a moved pointer selects the row under it", tall.selectedIndex, 0);
            tall.moveSelection(3);
            probe.check("keys: Down x3 from the hovered row", tall.selectedIndex, 3);
            tall.noteHover(1, Qt.point(10, 10));
            probe.check("hover: the list scrolling under a resting pointer keeps the key selection", tall.selectedIndex, 3);
            tall.noteHover(1, Qt.point(10, 14));
            probe.check("hover: the pointer moving again selects", tall.selectedIndex, 1);
            tall.visible = false;
            tall.visible = true;
            afterOpen.start();
        }
    }

    // the reveal runs from Qt.callLater and, without sizes, from the list's geometry
    Timer {
        id: afterOpen
        interval: 200; repeat: false
        onTriggered: {
            probe.check("tall: twelve rows", tall.rowCount, 12);
            probe.check("tall: highlight on the last (current) row", tall.selectedIndex, 11);
            probe.check("tall: the current row opened inside the viewport", tall.rowInView(11), true);
            probe.check("tall: the first row is scrolled out (the list is capped)", tall.rowInView(0), false);
            probe.check("tall: no reveal left pending", tall.pendingReveal, -1);
            tall.moveSelection(-11);
            probe.check("tall: Up to the first row brings it into view", [tall.selectedIndex, tall.rowInView(0)], [0, true]);
            // A reveal left pending (no sizes at callLater time) runs from the
            // geometry that lands afterwards. No polish loop runs here, so the
            // row's own height change stands in for the layout's.
            tall.pendingReveal = 11;
            tall.rowAt(11).height += 1;
            probe.check("tall: a pending reveal runs on the row's next geometry change", [tall.pendingReveal, tall.rowInView(11)], [-1, true]);

            console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
            Qt.quit();
        }
    }
}
QML

out="$(cd "$WORK/shell" && PATH="$WORK/bin:$PATH" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 60 qs -p model_picker_probe.qml 2>&1)"
echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^ DEBUG qml: //p' | grep -E '^(PASS|FAIL|PROBE)' || true
if ! grep -q "PROBE OK" <<< "$out"; then
    echo "--- probe output ---" >&2
    echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -vE "qmlscanner|^\s*$" >&2
    fail "the ModelPicker probe did not pass"
fi

echo "ok   model picker: three rows, the current one marked, keys and a click report the id through picked; a current row past the fold opens in view; hover selects only on pointer movement"
