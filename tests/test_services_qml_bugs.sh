#!/usr/bin/env bash
# The services fixed in J18, driven for real without touching the session:
# singletons load from a symlinked shell root with XDG_* in a temp dir, and the
# binaries they call are PATH shims that log what they were asked. Services
# that need the bus, keyring, clipboard or audio are checked at the source line.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
SERVICES="$SHELL_ROOT/services"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'KeyringStorage.keyringData?.apiKeys?.\[id\] ?? ""' "$SERVICES/MemoryService.qml" \
    || fail "MemoryService reads the embedding key through ?.key again (keys are strings)"
grep -q 'if (!notifObject) {' "$SERVICES/Notifications.qml" \
    || fail "Notifications NotifTimer dereferences a notification that may already be discarded"
grep -q "cleanedCommand.trim().startsWith('sudo')" "$SERVICES/LauncherSearch.qml" \
    || fail "LauncherSearch tests the raw query for sudo instead of the command it runs"
grep -q 'Number.isNaN(value)' "$SERVICES/Ai.qml" \
    || fail "Ai.setTemperature compares against NaN with ==, which is never true"
grep -q 'Math.max(0, Audio.sink.audio.volume - step)' "$SERVICES/Audio.qml" \
    || fail "Audio.decrementVolume has no floor at 0"
grep -q '0.02 || 0.2' "$SERVICES/Audio.qml" \
    && fail "Audio still carries the dead '|| 0.2' step fallback"
grep -q 'Mpris.players.values\[0\]' "$SERVICES/MprisController.qml" \
    || fail "MprisController indexes the ObjectModel directly (Mpris.players[0] is undefined)"
grep -q 'Qt.createQmlObject' "$SERVICES/LatexRenderer.qml" \
    && fail "LatexRenderer builds QML source from the user's expression again"
echo "ok   source: guarded lines present in MemoryService, Notifications, LauncherSearch, Ai, Audio, MprisController, LatexRenderer"

# /usr/bin/qmllint is Qt 5 and rejects list<var> and pragma ComponentBehavior
QMLLINT=/usr/lib/qt6/bin/qmllint
if [[ -x "$QMLLINT" ]]; then
    LINT="$(mktemp -d)"
    ln -s "$SHELL_ROOT" "$LINT/qs"
    for f in MemoryService Notifications LauncherSearch HyprlandXkb Wallpapers Cliphist Emojis Privacy Ai Updates MprisController Audio EasyEffects LatexRenderer; do
        out="$("$QMLLINT" -I "$LINT" -I /usr/lib/qt6/qml "$SERVICES/$f.qml" 2>&1)" \
            || { echo "$out" | head -20 >&2; fail "qmllint rejects services/$f.qml"; }
        grep -qE '^Error' <<< "$out" && { echo "$out" | grep -A3 '^Error' >&2; fail "qmllint error in services/$f.qml"; }
    done
    rm -rf "$LINT"
    echo "ok   qmllint: 14 touched services parse without errors"
else
    echo "skip: no Qt 6 qmllint at $QMLLINT"
fi

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/xdg/config/hypr/hyprland/scripts" "$WORK/xdg/state" "$WORK/xdg/cache" "$WORK/bin" "$WORK/out"

# symlinks, the real tree carries the assets
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
cp "$REPO_ROOT/dots/.config/hypr/hyprland/scripts/fuzzel-emoji.sh" "$WORK/xdg/config/hypr/hyprland/scripts/"

cat > "$WORK/bin/cliphist" <<'SH'
#!/usr/bin/env bash
if [[ "$1" == delete ]]; then printf 'delete %s\n' "$(cat)" >> "$SHIM_LOG"; exit 0; fi
printf '%s\n' "$1" >> "$SHIM_LOG"
exit 0
SH
cat > "$WORK/bin/checkupdates" <<'SH'
#!/usr/bin/env bash
mode="$(cat "$SHIM_MODE")"
case "$mode" in
    updates) printf 'foo 1-1 -> 1-2\nbar 2-1 -> 2-2\nbaz 3-1 -> 3-2\n'; exit 0 ;;
    none) exit 2 ;;
    *) echo "error: cannot fetch updates" >&2; exit 1 ;;
esac
SH
cat > "$WORK/bin/hyprctl" <<'SH'
#!/usr/bin/env bash
printf '{"keyboards":[{"main":true,"layout":"us,kh","variant":"intl,","active_keymap":"English (US, intl., with dead keys)"}]}\n'
SH
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/easyeffects"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/flatpak"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/pidof"
printf '#!/usr/bin/env bash\nexit 0\n' > "$WORK/bin/pkill"
chmod +x "$WORK/bin"/*
: > "$WORK/shim.log"
echo failing > "$WORK/checkupdates.mode"

cat > "$WORK/shell/services_probe.qml" <<'QML'
import qs.services
import qs.modules.common.functions
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import QtQuick

ShellRoot {
    id: probe
    property string work: Quickshell.env("PROBE_WORK")
    property int failures: 0
    property int stage: 0

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
    Process { id: modeWriter }

    property list<string> latexDone: []
    Connections {
        target: LatexRenderer
        function onRenderFinished(hash, imagePath) { probe.latexDone.push(imagePath); }
    }

    Component.onCompleted: {
        const stored = { apiKeys: { gemini: "sk-test" } };
        probe.check("H7 apiKeys.<id> is the key string", (stored?.apiKeys?.["gemini"] ?? "") === "sk-test"
            && (stored?.apiKeys?.["gemini"]?.key ?? "") === "", "the old ?.key read yields empty");
        probe.check("L4 Number.isNaN catches a bad temperature", Number.isNaN(parseFloat("abc")) && !(parseFloat("abc") == NaN));
        const cleaned = StringUtils.cleanPrefix("$sudo pacman -Syu", "$");
        probe.check("M8 prefixed sudo is detected on the cleaned command", cleaned.trim().startsWith("sudo") && !"$sudo pacman -Syu".startsWith("sudo"));

        probe.check("L7 Mpris.players[0] is undefined, .values is the list", Mpris.players[0] === undefined && typeof Mpris.players.values.length === "number");

        const sharing = Pipewire.linkGroups.values.some(g => g.source.type === PwNodeType.VideoSource);
        const mic = Pipewire.linkGroups.values.some(g => g.source.type === PwNodeType.AudioSource && g.target.type === PwNodeType.AudioInStream);
        probe.check("L3 Privacy.screenSharing matches the link groups", Privacy.screenSharing === sharing, "sharing=" + sharing);
        probe.check("L3 Privacy.micActive matches the link groups", Privacy.micActive === mic, "mic=" + mic);

        // touching the singleton starts the shimmed hyprctl fetch now
        console.log("xkb layouts at start: " + HyprlandXkb.layoutCodes.length);

        Cliphist.deleteEntry("1\tfirst entry");
        Cliphist.deleteEntry("2\tsecond entry");

        Updates.available = true;
        Updates.count = 7;
        Updates.refresh();

        Wallpapers.setDirectory("/nonexistent/j18/wallpapers");

        EasyEffects.enable();
        probe.check("L12 enable() is optimistic", EasyEffects.active === true);

        Emojis.load();

        LatexRenderer.latexOutputPath = probe.work + "/out";
        LatexRenderer.requestRender('\\text{"hi"}\n\\frac{1}{2}');
        LatexRenderer.latexOutputPath = probe.work + "/out/missing";
        LatexRenderer.requestRender('\\frac{3}{4}');
    }

    Timer {
        interval: 2500; running: true; repeat: true
        onTriggered: {
            probe.stage++;
            if (probe.stage === 1) {
                const log = probe.readFile(probe.work + "/shim.log");
                probe.check("M16 both deletions ran, then a refresh",
                    log.indexOf("delete 1\tfirst entry") >= 0 && log.indexOf("delete 2\tsecond entry") >= 0
                        && log.indexOf("list") > log.indexOf("delete 2"),
                    JSON.stringify(log));

                probe.check("L5 failed check keeps the last good count", Updates.count === 7, "count=" + Updates.count);
                modeWriter.exec(["bash", "-c", "echo updates > '" + probe.work + "/checkupdates.mode'"]);

                probe.check("M14 invalid directory left the folder alone",
                    Wallpapers.effectiveDirectory.indexOf("/nonexistent/") < 0, Wallpapers.effectiveDirectory);
                Wallpapers.setDirectory(probe.work + "/out");

                probe.check("L12 failed launch reads back as inactive", EasyEffects.active === false);

                probe.check("M13 layoutCodes carry the variant as base.lst does",
                    JSON.stringify(HyprlandXkb.layoutCodes) === JSON.stringify(["us:intl", "kh"]), JSON.stringify(HyprlandXkb.layoutCodes));
                probe.check("M13 the active variant layout matches an entry",
                    HyprlandXkb.currentLayoutCode === "us:intl" && HyprlandXkb.layoutCodes.includes(HyprlandXkb.currentLayoutCode),
                    HyprlandXkb.currentLayoutCode);

                Emojis.sloppySearch = false;
                const fuzzy = Emojis.fuzzyQuery("smile").length;
                Emojis.sloppySearch = true;
                let sloppy = -1;
                try { sloppy = Emojis.fuzzyQuery("smile").length; } catch (e) { console.log("sloppy threw: " + e); }
                probe.check("L2 sloppy emoji search works on the loaded list", fuzzy > 0 && sloppy > 0, "fuzzy=" + fuzzy + " sloppy=" + sloppy + " list=" + Emojis.list.length);

                probe.check("L13 quoted multi-line expression rendered to an existing file",
                    probe.latexDone.length === 1 && probe.readFile(probe.latexDone[0]).indexOf("<svg") >= 0, JSON.stringify(probe.latexDone));
                probe.check("L13 failed render is not marked processed", LatexRenderer.processedHashes.length === 1, JSON.stringify(LatexRenderer.processedHashes));
            } else if (probe.stage === 2) {
                Updates.refresh();
            } else if (probe.stage === 3) {
                probe.check("L5 a successful check counts the lines", Updates.count === 3, "count=" + Updates.count);
                probe.check("M14 valid directory applied", Wallpapers.effectiveDirectory === probe.work + "/out", Wallpapers.effectiveDirectory);
                console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
                Qt.quit();
            }
        }
    }
}
QML

[[ -x /opt/MicroTeX/LaTeX ]] || echo "note: /opt/MicroTeX/LaTeX missing, the L13 render checks will fail"

out="$(cd "$WORK/shell" && PATH="$WORK/bin:$PATH" SHIM_LOG="$WORK/shim.log" SHIM_MODE="$WORK/checkupdates.mode" PROBE_WORK="$WORK" \
    XDG_CONFIG_HOME="$WORK/xdg/config" XDG_STATE_HOME="$WORK/xdg/state" XDG_CACHE_HOME="$WORK/xdg/cache" \
    timeout 120 qs -p services_probe.qml 2>&1)"
echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^ DEBUG qml: //p' | grep -E '^(PASS|FAIL|PROBE)' || true

if ! grep -q "PROBE OK" <<< "$out"; then
    echo "--- probe output ---" >&2
    echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -vE "qmlscanner|^\s*$" >&2
    exit 1
fi

echo "ok   services: cliphist queue, checkupdates exit codes, xkb variants, wallpaper dir validation, easyeffects readback, emoji sloppy search, latex argv and exit code"
