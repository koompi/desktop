#!/usr/bin/env bash
# J43: the shell honours koompi-notify-send's "koompi-exec-argv" hint. Static: the
# invocation is the exact `bash -lc 'exec "$@"' --` form the sender's contract names,
# and the click path calls it. Live: the Notifications singleton is driven under a
# private bus (dbus-run-session, so the session's notification server is never
# displaced), fed a real --exec hint and a malformed one through busctl, and the
# argv it runs must land on disk with its spaces and dashes intact.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SERVICE="$SHELL_ROOT/services/Notifications.qml"
ITEM="$SHELL_ROOT/modules/common/widgets/NotificationItem.qml"
SENDER="$REPO_ROOT/dots/.local/bin/koompi-notify-send"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -qF 'return ["bash", "-lc", '"'"'exec "$@"'"'"', "--"].concat(argv);' "$SERVICE" \
    || fail "Notifications.execCommand is not the exact bash -lc 'exec \"\$@\"' -- form"
grep -qE 'notification\?\.hints\["koompi-exec-argv"\]' "$SERVICE" \
    || fail "Notifications.Notif does not read the koompi-exec-argv hint"
grep -qE 'sh", *"-c' "$SERVICE" \
    && fail "Notifications runs something through sh -c"
grep -q 'Notifications.invokeExec(notificationObject.notificationId)' "$ITEM" \
    || fail "NotificationItem's left-click does not call Notifications.invokeExec"
GROUP="$SHELL_ROOT/modules/common/widgets/NotificationGroup.qml"
grep -q 'Notifications.invokeExec(root.notifications\[0\].notificationId)' "$GROUP" \
    || fail "NotificationGroup's title-row click does not run the exec hint of a single collapsed toast"
grep -q 'interactive: expanded || root.hasExec' "$ITEM" \
    || fail "NotificationItem lets the left press fall through to the group when the hint is set"
grep -q 'invokeExec(notif.notificationId)' "$SERVICE" \
    || fail "invokeLast does not fall back to the exec hint"
# shellcheck disable=SC2016  # the literal contract line, no expansion wanted
grep -qF 'bash -lc '"'"'exec "$@"'"'"' -- "${argv[@]}"' "$SENDER" \
    || fail "koompi-notify-send no longer states the invocation its consumer must use"
grep -q 'services/Notifications.qml' "$SENDER" \
    || fail "koompi-notify-send does not name its consumer"
for f in "$SERVICE" "$ITEM"; do
    lines="$(wc -l < "$f")"
    (( lines <= 400 )) || fail "$(basename -- "$f") is $lines lines, cap is 400"
done
echo "ok   source: exact exec form, hint read, click path, invokeLast fallback, both files under 400 lines"

# /usr/bin/qmllint is Qt 5 and rejects list<var> and pragma ComponentBehavior
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    LINT="$(mktemp -d)"
    ln -s "$SHELL_ROOT" "$LINT/qs"
    for f in "$SERVICE" "$ITEM"; do
        out="$("$QMLLINT" -I "$LINT" -I /usr/lib/qt6/qml "$f" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects $(basename -- "$f")"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in $(basename -- "$f")"; }
    done
    rm -rf "$LINT"
    echo "ok   qmllint: Notifications.qml and NotificationItem.qml parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

for tool in qs dbus-run-session busctl jq; do
    command -v "$tool" > /dev/null 2>&1 || { echo "skip: $tool not installed, static checks only"; exit 0; }
done

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/xdg/config" "$WORK/xdg/state" "$WORK/xdg/cache"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

# Two notifications on the private bus: one --exec whose argv writes "$@" to a file
# (so a joined or re-split argv would show), one with a hint that is not JSON. The
# server owns its name a moment after the singleton loads, hence the retry.
cat > "$WORK/send.sh" <<SH
#!/usr/bin/env bash
set -uo pipefail
for _ in \$(seq 50); do
    "$SENDER" -a probe "runs" "argv to file" --exec sh -c 'printf "%s\\n" "\$@" > "\$0"' "$WORK/out.txt" "hi there" "--x" && break
    sleep 0.1
done
busctl --user call org.freedesktop.Notifications /org/freedesktop/Notifications \\
    org.freedesktop.Notifications Notify "susssasa{sv}i" -- probe 0 "" "malformed" "hint is not json" 0 \\
    1 koompi-exec-argv s "not json" -1 > /dev/null
SH
chmod +x "$WORK/send.sh"

cat > "$WORK/shell/exec_hint_probe.qml" <<'QML'
import qs.services
import Quickshell
import Quickshell.Io
import QtQuick

ShellRoot {
    id: probe
    property string work: Quickshell.env("PROBE_WORK")
    property int failures: 0
    property int stage: 0
    property var seen: []
    property var expectedArgv: ["sh", "-c", 'printf "%s\\n" "$@" > "$0"', work + "/out.txt", "hi there", "--x"]

    function check(label, ok, detail) {
        console.log((ok ? "PASS " : "FAIL ") + label + (detail ? "  " + detail : ""));
        if (!ok) probe.failures++;
    }
    function readFile(path) {
        const view = fileReader.createObject(probe, { path: path });
        const text = view.text();
        view.destroy();
        return text;
    }
    Component { id: fileReader; FileView { blockLoading: true } }
    Connections {
        target: Notifications
        function onNotify(notif) { probe.seen.push(notif); }
    }
    Process { id: sender; command: [probe.work + "/send.sh"] }

    Component.onCompleted: {
        const argv = Notifications.parseExecArgv('["echo","hi there","--x"]');
        probe.check("parse keeps spaces and dashes", JSON.stringify(argv) === '["echo","hi there","--x"]', JSON.stringify(argv));
        let threw = false;
        let malformed = [];
        try {
            malformed = ["not json", '{"a":1}', '[1,2]', '["a",1]', "[]", "", undefined, null].map((hint) => Notifications.parseExecArgv(hint));
        } catch (e) { threw = true; }
        probe.check("malformed hints yield [] and never throw", !threw && malformed.every((argv) => argv.length === 0), JSON.stringify(malformed));
        probe.check("execCommand is bash -lc 'exec \"$@\"' -- argv",
            JSON.stringify(Notifications.execCommand(argv)) === JSON.stringify(["bash", "-lc", 'exec "$@"', "--", "echo", "hi there", "--x"]),
            JSON.stringify(Notifications.execCommand(argv)));
        probe.check("invokeExec on an unknown id is false", Notifications.invokeExec(999999) === false);
        sender.running = true;
    }

    Timer {
        interval: 2000; running: true; repeat: true
        onTriggered: {
            probe.stage++;
            if (probe.stage === 1) {
                probe.check("both notifications arrived over the bus", probe.seen.length === 2, "seen=" + probe.seen.length);
                const good = probe.seen.find((n) => n.summary === "runs");
                const bad = probe.seen.find((n) => n.summary === "malformed");
                probe.check("Notif.execArgv is the argv koompi-notify-send encoded",
                    JSON.stringify(good?.execArgv) === JSON.stringify(probe.expectedArgv), JSON.stringify(good?.execArgv));
                probe.check("a malformed hint keeps the notification with execArgv []", bad !== undefined && bad.execArgv.length === 0);
                probe.check("execArgv is not persisted (notifToJSON omits it)", good !== undefined && !("execArgv" in Notifications.notifToJSON(good)));
                probe.check("invokeExec runs and discards", good !== undefined && Notifications.invokeExec(good.notificationId) === true
                    && !Notifications.list.some((n) => n.notificationId === good.notificationId));
            } else if (probe.stage === 2) {
                const out = probe.readFile(probe.work + "/out.txt");
                probe.check("the argv reached exec intact", out === "hi there\n--x\n", JSON.stringify(out));
                console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
                Qt.quit();
            }
        }
    }
}
QML

# A bus with no service directories: the stock session config would activate
# xdg-desktop-portal for the probe's quickshell, and its Hyprland backend
# segfaults on a bus that is not the session's (a coredump koompi-crash-watch
# would announce on every suite run).
cat > "$WORK/bus.conf" <<'CONF'
<!DOCTYPE busconfig PUBLIC "-//freedesktop//DTD D-Bus Bus Configuration 1.0//EN"
 "http://www.freedesktop.org/standards/dbus/1.0/busconfig.dtd">
<busconfig>
  <type>session</type>
  <listen>unix:tmpdir=/tmp</listen>
  <policy context="default">
    <allow send_destination="*" eavesdrop="true"/>
    <allow eavesdrop="true"/>
    <allow own="*"/>
  </policy>
</busconfig>
CONF
out="$(cd "$WORK/shell" && PROBE_WORK="$WORK" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 60 dbus-run-session --config-file="$WORK/bus.conf" -- qs -p exec_hint_probe.qml 2>&1)"
echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^ DEBUG qml: //p' | grep -E '^(PASS|FAIL|PROBE)' || true

if ! grep -q "PROBE OK" <<< "$out"; then
    echo "--- probe output ---" >&2
    echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -vE "qmlscanner|^\s*$" >&2
    exit 1
fi
grep -q "Ignoring malformed koompi-exec-argv hint" <<< "$out" || fail "the malformed hint was not logged"

echo "ok   probe: hint parsed over a real bus, argv preserved through bash -lc 'exec \"\$@\"' --, malformed hint logged and dropped"
