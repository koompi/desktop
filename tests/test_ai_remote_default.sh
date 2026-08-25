#!/usr/bin/env bash
# J27: 0xAlpha (stealth/ox-alpha via tokenra) is the default remote model and
# routes to its own endpoint, key slot and key link instead of the generic
# "name with a slash is OpenRouter" rule. ModelRegistry is driven for real with
# `qs -p` from a symlinked shell root, XDG_* in a temp dir and secret-tool /
# ollama shimmed, so no keyring, socket or session is touched. Three runs of
# the probe cover the states.json cases:
#   none        -> the shipped default applies
#   remoteModel -> the user's own choice is kept (JsonAdapter: a key present in
#                  the file overrides the QML default; koompi-migrate merges
#                  config.json only and never touches states.json)
#   key absent  -> the new default fills the gap
# A fourth run (J28) starts from a stored deepseek-chat + remoteEndpoint and
# calls setModel("") and setModel("   "), which is what `/model` with no
# argument reaches ModelRegistry as: the state must survive both, in memory and
# in the states.json written back, and each call answers with the current
# model and the usage line.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"
OXALPHA_ENDPOINT="https://tokenra.io/v1/chat/completions"

fail() { printf 'FAIL: %s\n' "$1" >&2; exit 1; }

grep -q 'property string remoteModel: "stealth/ox-alpha"' "$SHELL_ROOT/modules/common/Persistent.qml" \
    || fail "Persistent.qml no longer ships stealth/ox-alpha as the remoteModel default"
grep -q '?? "gemini-2.5-flash"' "$SHELL_ROOT/services/ai/ModelRegistry.qml" \
    && fail "ModelRegistry still falls back to gemini-2.5-flash somewhere"
[[ -f "$SHELL_ROOT/assets/icons/oxalpha-symbolic.svg" ]] \
    || fail "guessModelLogo names oxalpha-symbolic but assets/icons/oxalpha-symbolic.svg is missing"
grep -rqE 'sk-[A-Za-z0-9]{20,}|Bearer [A-Za-z0-9._-]{20,}' "$SHELL_ROOT/services/ai" "$SHELL_ROOT/modules/common" "$REPO_ROOT/tests" \
    && fail "something that looks like an API key is in the tree"
echo "ok   source: default is stealth/ox-alpha, no gemini fallback, icon file present, no key material"

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/bin"
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/ollama"
printf '#!/usr/bin/env bash\nexit 1\n' > "$WORK/bin/secret-tool"
chmod +x "$WORK/bin"/*

cat > "$WORK/shell/remote_default_probe.qml" <<'QML'
import qs.modules.common
import qs.services.ai
import Quickshell
import QtQuick

ShellRoot {
    id: probe
    property int failures: 0
    property string expectRemote: Quickshell.env("PROBE_EXPECT_REMOTE")
    property string expectEndpoint: Quickshell.env("PROBE_EXPECT_ENDPOINT")
    property bool emptyArg: Quickshell.env("PROBE_EMPTY_ARG") === "1"
    property var messages: []

    function check(label, got, want) {
        const ok = got === want;
        console.log((ok ? "PASS " : "FAIL ") + label + "  got=" + JSON.stringify(got) + (ok ? "" : " want=" + JSON.stringify(want)));
        if (!ok) probe.failures++;
    }

    // the facade the registry talks back to; nothing is displayed here
    QtObject {
        id: engine
        property string interfaceRole: "interface"
        property bool requestActive: false
        function addMessage(text, role) {
            probe.messages.push(text);
            console.log("engine message: " + text.replace(/\n+/g, " | "));
        }
    }
    ModelRegistry { id: registry; engine: engine }

    Component.onCompleted: {
        probe.check("infer endpoint stealth/ox-alpha", registry.inferEndpointForModel("stealth/ox-alpha"), "https://tokenra.io/v1/chat/completions");
        probe.check("infer api_format stealth/ox-alpha", registry.inferApiFormatForModel("stealth/ox-alpha"), "openai");
        probe.check("infer key_id stealth/ox-alpha", registry.inferKeyIdForModel("stealth/ox-alpha"), "oxalpha");
        probe.check("infer key_get_link stealth/ox-alpha", registry.inferProvider("stealth/ox-alpha").key_get_link, "https://oxalpha.io/ox-alpha-api.html");
        probe.check("infer key_id Stealth/OX-ALPHA (case)", registry.inferKeyIdForModel("Stealth/OX-ALPHA"), "oxalpha");
        probe.check("name stealth/ox-alpha", registry.guessModelName("stealth/ox-alpha"), "0xAlpha");
        probe.check("logo stealth/ox-alpha", registry.guessModelLogo("stealth/ox-alpha"), "oxalpha-symbolic");

        // regression rows: what these inferred before J27
        probe.check("infer endpoint gemini-2.5-flash", registry.inferEndpointForModel("gemini-2.5-flash"), "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:streamGenerateContent");
        probe.check("infer api_format gemini-2.5-flash", registry.inferApiFormatForModel("gemini-2.5-flash"), "gemini");
        probe.check("infer key_id gemini-2.5-flash", registry.inferKeyIdForModel("gemini-2.5-flash"), "gemini");
        probe.check("infer endpoint deepseek/x", registry.inferEndpointForModel("deepseek/x"), "https://openrouter.ai/api/v1/chat/completions");
        probe.check("infer api_format deepseek/x", registry.inferApiFormatForModel("deepseek/x"), "openai");
        probe.check("infer key_id deepseek/x", registry.inferKeyIdForModel("deepseek/x"), "openrouter");
        probe.check("logo deepseek/x", registry.guessModelLogo("deepseek/x"), "openrouter-symbolic");
        probe.check("infer endpoint deepseek-chat", registry.inferEndpointForModel("deepseek-chat"), "https://api.deepseek.com/chat/completions");
        probe.check("infer key_id deepseek-chat", registry.inferKeyIdForModel("deepseek-chat"), "deepseek");
        probe.check("infer api_format mistral-large", registry.inferApiFormatForModel("mistral-large"), "mistral");
        probe.check("infer key_id gpt-4.1", registry.inferKeyIdForModel("gpt-4.1"), "openai");
        probe.check("infer endpoint unknown name", registry.inferEndpointForModel("whatever-7b"), "https://api.openai.com/v1/chat/completions");
        probe.check("infer key_id unknown name", registry.inferKeyIdForModel("whatever-7b"), "custom");
        probe.check("name gemini-2.5-flash unchanged", registry.guessModelName("gemini-2.5-flash"), "Gemini 2.5 (Flash)");
    }

    // Persistent's FileView loads asynchronously; the remote slot is read once it has
    Timer {
        interval: 1500; running: true; repeat: false
        onTriggered: {
            probe.check("Persistent ready", Persistent.ready, true);
            probe.check("remote slot model", registry.remoteModelObj.model, probe.expectRemote);
            probe.check("remote slot endpoint", registry.remoteModelObj.endpoint, probe.expectEndpoint);
            if (probe.expectRemote === "stealth/ox-alpha") {
                probe.check("remote slot api_format", registry.remoteModelObj.api_format, "openai");
                probe.check("remote slot key_id", registry.remoteModelObj.key_id, "oxalpha");
                probe.check("remote slot requires_key", registry.remoteModelObj.requires_key, true);
                probe.check("remote slot key_get_link", registry.remoteModelObj.key_get_link, "https://oxalpha.io/ox-alpha-api.html");
                probe.check("remote slot logo", registry.remoteModelObj.icon, "oxalpha-symbolic");
            }
            probe.check("current model id", registry.currentModelId, "remote");
            if (probe.emptyArg) probe.emptyArgCase();
            else probe.finish();
        }
    }

    // `/model` with no argument: the command passes args[0] (undefined) on,
    // and a line of spaces trims to the same thing
    function emptyArgCase() {
        const ai = Persistent.states.ai;
        const before = { model: ai.model, remoteModel: ai.remoteModel, remoteEndpoint: ai.remoteEndpoint, remoteFormat: ai.remoteFormat };
        probe.messages = [];
        registry.setModel("");
        registry.setModel("   ");
        probe.check("empty arg: ai.model kept", ai.model, before.model);
        probe.check("empty arg: remoteModel kept", ai.remoteModel, before.remoteModel);
        probe.check("empty arg: remoteEndpoint kept", ai.remoteEndpoint, before.remoteEndpoint);
        probe.check("empty arg: remoteFormat kept", ai.remoteFormat, before.remoteFormat);
        probe.check("empty arg: remote slot endpoint kept", registry.remoteModelObj.endpoint, before.remoteEndpoint);
        probe.check("empty arg: one reply per call", probe.messages.length, 2);
        for (let i = 0; i < probe.messages.length; i++) {
            probe.check("empty arg: reply " + i + " names the current model", probe.messages[i].includes(before.remoteModel), true);
            probe.check("empty arg: reply " + i + " carries the usage line",
                ["/model remote NAME", "/model local:NAME", "/model local"].every(u => probe.messages[i].includes(u)), true);
        }
        // Persistent writes 100ms after an adapter change; give a wipe time to land
        settle.start();
    }
    Timer { id: settle; interval: 500; repeat: false; onTriggered: probe.finish() }

    function finish() {
        console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
        Qt.quit();
    }
}
QML

# run_probe <label> <expected remoteModel> <expected endpoint> [states.json body]
run_probe() {
    local label="$1" expect_remote="$2" expect_endpoint="$3" states="${4:-}"
    local xdg="$WORK/xdg-$label"
    mkdir -p "$xdg/config" "$xdg/state/quickshell" "$xdg/cache"
    [[ -z "$states" ]] || printf '%s\n' "$states" > "$xdg/state/quickshell/states.json"
    echo "--- states.json: ${states:-(none)}"
    local out
    out="$(cd "$WORK/shell" && PATH="$WORK/bin:$PATH" PROBE_EXPECT_REMOTE="$expect_remote" PROBE_EXPECT_ENDPOINT="$expect_endpoint" \
        PROBE_EMPTY_ARG="${PROBE_EMPTY_ARG:-}" \
        XDG_CONFIG_HOME="$xdg/config" XDG_STATE_HOME="$xdg/state" XDG_CACHE_HOME="$xdg/cache" \
        timeout 60 qs -p remote_default_probe.qml 2>&1)"
    echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^ DEBUG qml: //p' | grep -E '^(PASS|FAIL|PROBE|engine message)' || true
    if ! grep -q "PROBE OK" <<< "$out"; then
        echo "--- probe output ($label) ---" >&2
        echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -vE "qmlscanner|^\s*$" >&2
        fail "probe '$label' did not pass"
    fi
    # the file the shell writes back carries the value the slot showed
    local written
    written="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["ai"]["remoteModel"])' "$xdg/state/quickshell/states.json" 2>/dev/null || echo "?")"
    [[ "$written" == "$expect_remote" ]] || fail "states.json written back with remoteModel=$written, want $expect_remote"
    # every ai key the input named comes back with the same value
    [[ -z "$states" ]] || python3 - "$xdg/state/quickshell/states.json" "$states" <<'PY' || fail "states.json written back differs from the one read ($label)"
import json, sys
written = json.load(open(sys.argv[1]))["ai"]
given = json.loads(sys.argv[2])["ai"]
diff = {k: (v, written.get(k)) for k, v in given.items() if written.get(k) != v}
for k, (want, got) in diff.items():
    print(f"  ai.{k}: read {want!r}, written {got!r}")
sys.exit(1 if diff else 0)
PY
}

run_probe fresh "stealth/ox-alpha" "$OXALPHA_ENDPOINT"
run_probe kept "deepseek-chat" "https://api.deepseek.com/chat/completions" \
    '{"ai":{"model":"remote","remoteModel":"deepseek-chat","remoteEndpoint":"","remoteFormat":""}}'
run_probe gap "stealth/ox-alpha" "$OXALPHA_ENDPOINT" '{"ai":{"model":"remote","temperature":0.5}}'
PROBE_EMPTY_ARG=1 run_probe empty "deepseek-chat" "https://example.test/v1/chat/completions" \
    '{"ai":{"model":"remote","remoteModel":"deepseek-chat","remoteEndpoint":"https://example.test/v1/chat/completions","remoteFormat":""}}'

echo "ok   remote default: stealth/ox-alpha infers tokenra/openai/oxalpha with its key link, regressions hold, a stored remoteModel survives, a missing one takes the default, /model with no argument keeps the state"
