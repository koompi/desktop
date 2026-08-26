#!/usr/bin/env bash
# J48: everything the desktop can do to itself is one flat index of leaves in
# services/CommandTree.qml, reachable by typing three letters. Groups are
# headings, not levels: there is no drilling and no back key. The static half
# reads the sources; the probe half loads the real singleton with `qs -p`,
# shimming koompi-hw-fingerprint and XDG_STATE_HOME so the two conditions that
# are not already held by a service can be driven both ways.
set -uo pipefail
# extglob so the ANSI escapes qs colours its log with can be stripped by a bash
# replacement instead of a sed round trip.
shopt -s extglob

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
TREE="$SHELL_ROOT/services/CommandTree.qml"
ENTRIES="$SHELL_ROOT/services/commandTree/Entries.qml"
CONDITIONS="$SHELL_ROOT/services/commandTree/Conditions.qml"
RESULT="$SHELL_ROOT/services/commandTree/CommandResult.qml"
LAUNCHER="$SHELL_ROOT/services/LauncherSearch.qml"
ITEM="$SHELL_ROOT/modules/koompi/overview/SearchItem.qml"
WIDGET="$SHELL_ROOT/modules/koompi/overview/SearchWidget.qml"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

for f in "$TREE" "$ENTRIES" "$CONDITIONS" "$RESULT" "$LAUNCHER" "$ITEM" "$WIDGET"; do
    [[ -f "$f" ]] || fail "missing $f"
done

# LauncherSearch is allow-listed at 508 and must not grow; the wiring is one line.
allow="$(awk -F'\t' '$1 == "dots/.config/quickshell/koompi/services/LauncherSearch.qml" { print $2 }' "$REPO_ROOT/tests/file-length-allow.txt")"
[[ "$allow" == "508" ]] || fail "the allow-list entry for LauncherSearch.qml is '$allow', expected 508"
lines="$(wc -l < "$LAUNCHER")"
(( lines <= 508 )) || fail "LauncherSearch.qml is $lines lines, cap is 508"
grep -q 'CommandTree.results(root.query)' "$LAUNCHER" || fail "LauncherSearch.qml does not call CommandTree.results"
(( $(grep -c 'CommandTree' "$LAUNCHER") == 1 )) || fail "the CommandTree wiring in LauncherSearch.qml is more than one line"
grep -q 'return root.recentResults();' "$LAUNCHER" || fail "the empty unprefixed query no longer answers with recents"
echo "ok   static: LauncherSearch.qml is $lines lines, wired in one line, still answers an empty query with recents"

for f in "$TREE" "$ENTRIES" "$CONDITIONS" "$RESULT" "$ITEM" "$WIDGET"; do
    lines="$(wc -l < "$f")"
    (( lines <= 400 )) || fail "$(basename -- "$f") is $lines lines, cap is 400"
done
echo "ok   static: every new or touched QML file outside the allow-list is under 400 lines"

# No timer and no per-keystroke process: conditions read what a service already keeps.
grep -q 'Timer' "$ENTRIES" && fail "Entries.qml introduces a Timer"
grep -q 'Timer' "$CONDITIONS" && fail "Conditions.qml introduces a Timer"
grep -q 'Timer' "$TREE" && fail "CommandTree.qml introduces a Timer"
grep -q 'Process' "$ENTRIES" && fail "Entries.qml spawns a process outside execute()"
(( $(grep -c 'Process {' "$CONDITIONS") == 1 )) || fail "Conditions.qml runs more than the one startup probe"
grep -q 'running: true' "$CONDITIONS" || fail "the fingerprint probe does not run once at load"
echo "ok   static: no timer anywhere, one one-shot probe, nothing spawned per keystroke"

# The row type is a LauncherSearchResult, so the panel treats a leaf like any
# other result and the keyboard handling is untouched.
grep -q '^LauncherSearchResult {' "$RESULT" || fail "CommandResult.qml is not a LauncherSearchResult"
for prop in group heading stateText; do
    grep -q "property string $prop" "$RESULT" || fail "CommandResult.qml has no $prop"
    grep -q "$prop" "$ITEM" || fail "SearchItem.qml does not read $prop"
done
grep -q 'Qt.Key_Return' "$ITEM" || fail "SearchItem.qml lost its Enter handling"
echo "ok   static: a leaf is a LauncherSearchResult with group, heading and state; Enter is unchanged"

QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    LINT="$(mktemp -d)"
    ln -s "$SHELL_ROOT" "$LINT/qs"
    for f in "$TREE" "$ENTRIES" "$CONDITIONS" "$RESULT" "$LAUNCHER" "$ITEM" "$WIDGET"; do
        out="$("$QMLLINT" -I "$LINT" -I /usr/lib/qt6/qml "$f" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects $(basename -- "$f")"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in $(basename -- "$f")"; }
    done
    rm -rf "$LINT"
    echo "ok   qmllint: the seven touched files parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin" "$WORK/xdg/config" "$WORK/xdg/cache" \
         "$WORK/reader/koompi/crash" "$WORK/noreader/koompi"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
# One crash report on the "reader" run, none on the other.
printf '# crash\n' > "$WORK/reader/koompi/crash/20260101-000000-probe-1.md"
# Nothing in the probe may reach the machine.
for stub in checkupdates snapper koompi-theme koompi-launch koompi-snapshot koompi-setup-fingerprint koompi-reload; do
    printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/$stub"
done
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/command_tree_probe.qml" <<'QML'
import qs.services
import Qt.labs.folderlistmodel
import Quickshell
import QtQuick

ShellRoot {
    id: probe
    property int failures: 0
    // Whether koompi-hw-fingerprint on PATH exits 0 for this run.
    readonly property bool wantReader: Quickshell.env("PROBE_READER") === "1"

    function check(label, got, want) {
        const ok = JSON.stringify(got) === JSON.stringify(want);
        console.log((ok ? "PASS " : "FAIL ") + label + "  got=" + JSON.stringify(got) + (ok ? "" : " want=" + JSON.stringify(want)));
        if (!ok) probe.failures++;
    }

    // What the panel would draw for one row.
    function render(row) {
        return [row.heading, row.name, row.stateText, row.group].join(" | ");
    }

    Timer {
        interval: 100
        repeat: true
        running: true
        property int waited: 0
        onTriggered: {
            const conditions = CommandTree.conditions;
            const settled = !conditions.readerProbe.running && conditions.crashReports.status === FolderListModel.Ready;
            waited += interval;
            if (!settled && waited < 8000)
                return;
            running = false;
            if (!settled) {
                console.log("FAIL  conditions never settled");
                probe.failures++;
            }
            probe.run();
        }
    }

    function run() {
        const entries = CommandTree.entries.all;
        const groupIds = CommandTree.entries.groups.map(group => group.id);

        probe.check("entries: the first set is 15 to 20 leaves", [entries.length >= 15, entries.length <= 20, entries.length], [true, true, 17]);
        probe.check("entries: every leaf has an id, a label, a group and something to run",
            entries.filter(e => !e.id || !e.label || !e.group || typeof e.execute !== "function").map(e => e.id ?? e.label), []);
        probe.check("entries: every group is one of the declared headings",
            entries.filter(e => !groupIds.includes(e.group)).map(e => e.id), []);
        probe.check("entries: no id collides", entries.length, new Set(entries.map(e => e.id)).size);
        probe.check("entries: every optional condition is a function",
            entries.filter(e => (e.when !== undefined && typeof e.when !== "function") || (e.state !== undefined && typeof e.state !== "function")).map(e => e.id), []);

        // `when` decides whether the row exists at all; nothing is greyed.
        const availableIds = CommandTree.available.map(e => e.id);
        probe.check("when: the fingerprint row follows the reader",
            availableIds.includes("system.fingerprint"), probe.wantReader);
        probe.check("when: the crash row follows a written report",
            availableIds.includes("system.crash-report"), probe.wantReader);
        probe.check("when: available is a subset of the entry set",
            availableIds.filter(id => !entries.some(e => e.id === id)), []);

        // Three letters, no prefix: the leaf is in the flat list with its group.
        const flat = CommandTree.results("nig");
        console.log("VIEW  flat 'nig':");
        flat.forEach(row => console.log("VIEW    " + probe.render(row)));
        probe.check("flat: 'nig' reaches night light first", flat.length > 0 ? flat[0].name : "", "Night light");
        probe.check("flat: the row carries its group as a trailing label", flat.length > 0 ? flat[0].group : "", "Toggles");
        probe.check("flat: a flat row has no heading", flat.length > 0 ? flat[0].heading : "!", "");
        probe.check("flat: the row shows the switch's state", ["on", "off"].includes(flat.length > 0 ? flat[0].stateText : ""), true);
        probe.check("flat: the leaves cannot crowd out the app list", flat.length <= CommandTree.flatLimit, true);
        probe.check("flat: an empty unprefixed query adds nothing, so recents stand", CommandTree.results(""), []);
        probe.check("flat: a query already inside another scope gets no leaves",
            [">nig", "#nig", "@nig", "~nig", ";nig", ":nig", "=nig", "$nig", "?nig"].map(q => CommandTree.results(q).length),
            [0, 0, 0, 0, 0, 0, 0, 0, 0]);

        // The action scope's empty state is the grouped view.
        const grouped = CommandTree.results("/");
        console.log("VIEW  action scope, empty:");
        grouped.forEach(row => console.log("VIEW    " + probe.render(row)));
        probe.check("grouped: every available leaf is listed", grouped.length, CommandTree.available.length);
        probe.check("grouped: the headings are the declared groups in order",
            grouped.filter(row => row.heading !== "").map(row => row.heading),
            CommandTree.entries.groups.filter(group => CommandTree.available.some(e => e.group === group.id)).map(group => group.label));
        probe.check("grouped: a heading opens its group and repeats nowhere",
            grouped.map(row => row.heading !== "").filter(Boolean).length,
            new Set(CommandTree.available.map(e => e.group)).size);
        probe.check("grouped: a headed row does not also carry the trailing label",
            grouped.filter(row => row.group !== "").length, 0);
        probe.check("grouped: the first heading is the first declared group", grouped.length > 0 ? grouped[0].heading : "", "Toggles");

        // Scoped and typed: the same flat match, uncapped, still with the label.
        const scoped = CommandTree.results("/nig");
        probe.check("scoped: '/nig' answers with the same leaf", scoped.length > 0 ? scoped[0].name : "", "Night light");
        probe.check("scoped: a typed scope row keeps its group label", scoped.length > 0 ? scoped[0].group : "", "Toggles");

        // A leaf is an ordinary Search row, so Enter runs it like any other.
        probe.check("row: a leaf is a LauncherSearchResult with a verb and an icon",
            flat.length > 0 ? [flat[0].verb, flat[0].iconName, typeof flat[0].execute] : [],
            ["Run", "bedtime", "function"]);

        console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
        Qt.quit();
    }
}
QML

run_probe() { # $1: 1 when the shimmed reader is present, $2: the XDG_STATE_HOME to use
    printf '#!/usr/bin/env bash\nexit %s\n' "$(( $1 == 1 ? 0 : 1 ))" > "$WORK/bin/koompi-hw-fingerprint"
    chmod +x "$WORK/bin/koompi-hw-fingerprint"
    (cd "$WORK/shell" && PATH="$WORK/bin:$PATH" PROBE_READER="$1" \
        XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$2" XDG_CACHE_HOME="$WORK/xdg/cache" \
        timeout 60 qs -p command_tree_probe.qml 2>&1)
}

for run in 0 1; do
    if (( run == 1 )); then
        label="a reader and a crash report on the machine"; state="$WORK/reader"
    else
        label="neither a reader nor a crash report"; state="$WORK/noreader"
    fi
    out="$(run_probe "$run" "$state")"
    plain="${out//$'\e'\[*([0-9;])m/}"
    printf -- '--- %s ---\n' "$label"
    grep -E '^ DEBUG qml: (PASS|FAIL|VIEW|PROBE)' <<< "$plain" | sed 's/^ DEBUG qml: //' || true
    if ! grep -q "PROBE OK" <<< "$plain"; then
        echo "--- probe output ---" >&2
        grep -vE "qmlscanner|^\s*$" <<< "$plain" >&2
        fail "the CommandTree probe did not pass with $label"
    fi
done

echo "ok   command tree: 17 leaves load with a group and a label, no id collides, a false when removes the row, 'nig' reaches night light flat and scoped, and the action scope's empty query groups them under their headings"
