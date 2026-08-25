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
# Two more runs (J44) drive Requester and Conversation against the registry:
#   gate  -> a keyed model with no key in the keyring answers with the /key
#            advice, keeps the user's turn, and spawns no curl (curl is shimmed
#            to a log, which must stay empty); ai.extraModels entries reach
#            modelList with their fields, a malformed one is skipped with a
#            warning; the context window is 131072 for an unknown hosted model,
#            8192 for an unknown local one, the entry's context_window when set
#   retry -> the same refusal, then /key and a plain retry send for real: the
#            log carries the endpoint and the bearer with the fake key
# Static half: neither OpenAI nor Mistral strategy can emit an empty bearer.
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

# The header is bash's ${VAR:+word}: with an empty key the whole -H disappears.
for strategy in OpenAiApiStrategy MistralApiStrategy; do
    f="$SHELL_ROOT/services/ai/$strategy.qml"
    grep -qF ':+-H "Authorization: Bearer \$\{${apiKeyEnvVarName}\}"\}`' "$f" \
        || fail "$strategy.buildAuthorizationHeader does not use \${KEY:+...} around the bearer header"
    grep -qF 'return `-H "Authorization: Bearer' "$f" \
        && fail "$strategy.buildAuthorizationHeader can still return a bare bearer header"
done
grep -q 'buildAuthorizationHeader(root.engine.apiKeyEnvVarName, model)' "$SHELL_ROOT/services/ai/Conversation.qml" \
    || fail "the compactor calls buildAuthorizationHeader without the model, so it sends no key"
grep -q 'root.keyGate.admit(model' "$SHELL_ROOT/services/ai/Requester.qml" \
    || fail "Requester.makeRequest does not pass through KeyGate.admit"
echo "ok   source: both strategies wrap the bearer in \${KEY:+...}, the compactor passes the model, the send path goes through KeyGate"

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
# lookup answers from PROBE_KEYRING (a fake keyring, no keys unless the run sets
# one); store swallows its stdin, so nothing reaches the real keyring
cat > "$WORK/bin/secret-tool" <<'SH'
#!/usr/bin/env bash
case "${1:-}" in
    lookup) printf '%s\n' "${PROBE_KEYRING:-{\"apiKeys\":{}}}" ;;
    *) cat > /dev/null ;;
esac
SH
# every curl the shell would run lands here instead of on the network
cat > "$WORK/bin/curl" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$CURL_LOG"
SH
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
    property string mode: Quickshell.env("PROBE_MODE")
    property var messages: []

    function check(label, got, want) {
        const ok = got === want;
        console.log((ok ? "PASS " : "FAIL ") + label + "  got=" + JSON.stringify(got) + (ok ? "" : " want=" + JSON.stringify(want)));
        if (!ok) probe.failures++;
    }

    // the facade the engine parts talk back to; nothing is displayed here
    QtObject {
        id: engine
        property string interfaceRole: "interface"
        property string apiKeyEnvVarName: "API_KEY"
        property bool requestActive: requester.running
        property var apiKeys: registry.apiKeys
        property var apiKeysLoaded: registry.apiKeysLoaded
        property var models: registry.models
        property string currentModelId: registry.currentModelId
        property var currentApiStrategy: registry.apiStrategies[engine.models[engine.currentModelId]?.api_format || "openai"]
        property Component aiMessageComponent: AiMessageData {}
        property var conversation: conversation
        property var requester: requester
        property var toolRunner: QtObject { function takeTurnSources() { return []; } }
        property var toolRegistry: null
        property var tools: ({ "openai": { "none": [] }, "mistral": { "none": [] }, "gemini": { "none": [] } })
        property string currentTool: "none"
        property string systemPrompt: ""
        property real temperature: 0.5
        property string pendingFilePath: ""
        property var postResponseHook: null
        property var tokenCount: ({ "input": -1, "output": -1, "total": -1 })
        property int compactionThreshold: 4096
        property bool compacting: false
        property string recalledMemories: ""
        property string sessionId: "probe"
        signal responseFinished()
        signal tokenStreamed()
        function addMessage(text, role) {
            if (role === engine.interfaceRole) probe.messages.push(text); // the shell's own replies
            console.log("engine message: " + text.replace(/\n+/g, " | "));
            conversation.addMessage(text, role);
        }
        function addApiKeyAdvice(model) { registry.addApiKeyAdvice(model); }
        function saveChat(name) {}
        function refreshSavedChats() {}
        function formatMemories(results) { return ""; }
        function compact(onDone) {}
    }
    ModelRegistry { id: registry; engine: engine }
    Requester { id: requester; engine: engine }
    Conversation { id: conversation; engine: engine }

    Timer { id: step; repeat: false; property var fn: null; onTriggered: { const f = step.fn; step.fn = null; f(); } }
    function after(ms, fn) { step.fn = fn; step.interval = ms; step.restart(); }
    function roles() { return conversation.messageIDs.map(id => conversation.messageByID[id].role); }

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
            if (probe.mode === "empty") probe.emptyArgCase();
            else if (probe.mode === "gate" || probe.mode === "retry") probe.extraModelsCase();
            else probe.finish();
        }
    }

    // (b) an ai.extraModels entry is a model under its id; (c) a malformed one is
    // skipped (the warning is asserted on the bash side); (d) the window chain
    function extraModelsCase() {
        probe.check("extra: in modelList", registry.modelList.indexOf("test/extra-1") !== -1, true);
        probe.check("extra: malformed entry not in modelList", registry.modelList.indexOf("test/broken") !== -1, false);
        probe.check("extra: remote slot still there", registry.modelList.indexOf("remote") !== -1, true);
        const extra = registry.models["test/extra-1"];
        probe.check("extra: model", extra?.model, "test/extra-1");
        probe.check("extra: name", extra?.name, "Probe Extra");
        probe.check("extra: endpoint", extra?.endpoint, "https://example.test/v1/chat/completions");
        probe.check("extra: api_format", extra?.api_format, "openai");
        probe.check("extra: key_id", extra?.key_id, "extra");
        probe.check("extra: requires_key", extra?.requires_key, true);
        probe.check("extra: key_get_link", extra?.key_get_link, "https://example.test/keys");
        probe.check("extra: icon", extra?.icon, "spark-symbolic");
        probe.check("extra: description", extra?.description, "Probe | extra");
        probe.check("extra: contextWindow", extra?.contextWindow, 200000);

        registry.addModel("litert-probe", { "model": "probe-e4b", "endpoint": "http://127.0.0.1:9379/v1/chat/completions", "requires_key": false });
        registry.addModel("ollama-probe", { "model": "gemma3:4b", "endpoint": "http://localhost:11434/v1/chat/completions", "requires_key": false });
        registry.addModel("hosted-probe", { "model": "gpt-4o", "endpoint": "https://api.openai.com/v1/chat/completions", "requires_key": true });
        probe.check("window: shipped contextWindow config is 0", conversation.configuredWindow, 0);
        engine.currentModelId = "remote";
        probe.check("window: remote stealth/ox-alpha", conversation.contextWindow, 131072);
        probe.check("window: remote source", conversation.contextWindowSource, "fallback (hosted)");
        engine.currentModelId = "test/extra-1";
        probe.check("window: extra entry's context_window wins", conversation.contextWindow, 200000);
        engine.currentModelId = "litert-probe";
        probe.check("window: LiteRT-served unknown name unchanged", conversation.contextWindow, 8192);
        probe.check("window: LiteRT source", conversation.contextWindowSource, "fallback (local)");
        engine.currentModelId = "ollama-probe";
        probe.check("window: local gemma keeps the model default", conversation.contextWindow, 8192);
        engine.currentModelId = "hosted-probe";
        probe.check("window: hosted gpt-4o keeps the model default", conversation.contextWindow, 128000);
        engine.currentModelId = "remote";

        console.log("AUTH_TEMPLATE openai " + registry.apiStrategies.openai.buildAuthorizationHeader("API_KEY", registry.remoteModelObj));
        console.log("AUTH_TEMPLATE mistral " + registry.apiStrategies.mistral.buildAuthorizationHeader("API_KEY", registry.remoteModelObj));
        probe.gateCase();
    }

    // (a) the keyring has not been read yet: the send waits for it, then finds
    // no key and answers with the advice; the user's turn stays, curl never runs
    function gateCase() {
        probe.check("gate: keyring not loaded before the first send", registry.apiKeysLoaded, false);
        probe.messages = [];
        requester.sendUserMessage("hello without a key");
        probe.check("gate: nothing running while the keyring loads", requester.running, false);
        probe.after(1000, () => {
            probe.check("gate: keyring loaded by the wait", registry.apiKeysLoaded, true);
            probe.check("gate: still nothing running", requester.running, false);
            probe.check("gate: user turn kept", probe.roles().join(","), "user,interface");
            probe.check("gate: one interface message", probe.messages.length, 1);
            probe.check("gate: advice names /key", (probe.messages[0] ?? "").includes("/key"), true);
            probe.check("gate: advice carries the key link", (probe.messages[0] ?? "").includes("https://oxalpha.io/ox-alpha-api.html"), true);
            if (probe.mode === "retry") probe.retryCase();
            else probe.finish();
        });
    }

    // /key then a plain retry: the same turn goes out, through the curl shim
    function retryCase() {
        registry.setApiKey("sk-test-fake");
        probe.check("retry: key stored", registry.apiKeys.oxalpha, "sk-test-fake");
        requester.retryRequest();
        probe.after(1500, () => {
            probe.check("retry: request went out", probe.roles().join(","), "user,interface,interface,assistant");
            probe.check("retry: request finished", requester.running, false);
            probe.finish();
        });
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

# The memory daemon stays off (it would be the real one), and two extraModels
# entries: one complete, one without an endpoint.
CONFIG_JSON='{"ai":{"memory":{"enable":false},"extraModels":[
  {"model":"test/extra-1","name":"Probe Extra","endpoint":"https://example.test/v1/chat/completions","api_format":"openai",
   "key_id":"extra","requires_key":true,"key_get_link":"https://example.test/keys","icon":"spark-symbolic",
   "description":"Probe | extra","context_window":200000},
  {"model":"test/broken","name":"No endpoint"}
]}}'

# run_probe <label> <expected remoteModel> <expected endpoint> [states.json body]
run_probe() {
    local label="$1" expect_remote="$2" expect_endpoint="$3" states="${4:-}"
    local xdg="$WORK/xdg-$label"
    mkdir -p "$xdg/config/koompi" "$xdg/state/quickshell" "$xdg/cache" "$xdg/runtime" "$xdg/litert"
    printf '%s\n' "$CONFIG_JSON" > "$xdg/config/koompi/config.json"
    : > "$xdg/curl.log"
    [[ -z "$states" ]] || printf '%s\n' "$states" > "$xdg/state/quickshell/states.json"
    echo "--- states.json: ${states:-(none)}"
    local out
    # XDG_RUNTIME_DIR is where the request script goes, so the live shell's is left
    # alone; the compositor socket is reached by absolute path instead
    out="$(cd "$WORK/shell" && PATH="$WORK/bin:$PATH" PROBE_EXPECT_REMOTE="$expect_remote" PROBE_EXPECT_ENDPOINT="$expect_endpoint" \
        PROBE_MODE="${PROBE_MODE:-}" CURL_LOG="$xdg/curl.log" LITERT_LM_DIR="$xdg/litert" \
        WAYLAND_DISPLAY="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/${WAYLAND_DISPLAY:-wayland-1}" XDG_RUNTIME_DIR="$xdg/runtime" \
        XDG_CONFIG_HOME="$xdg/config" XDG_STATE_HOME="$xdg/state" XDG_CACHE_HOME="$xdg/cache" \
        timeout 60 qs -p remote_default_probe.qml 2>&1)"
    echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^ *\(DEBUG\|WARN\) qml: //p' | grep -E '^(PASS|FAIL|PROBE|engine message|AUTH_TEMPLATE|\[AI\] ai.extraModels)' || true
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
PROBE_MODE=empty run_probe empty "deepseek-chat" "https://example.test/v1/chat/completions" \
    '{"ai":{"model":"remote","remoteModel":"deepseek-chat","remoteEndpoint":"https://example.test/v1/chat/completions","remoteFormat":""}}'

echo "ok   remote default: stealth/ox-alpha infers tokenra/openai/oxalpha with its key link, regressions hold, a stored remoteModel survives, a missing one takes the default, /model with no argument keeps the state"

# what the probes above print is only checked for PASS/FAIL; these two runs also
# leave a curl log and a warning line behind
probe_out() { echo "$1" | sed 's/\x1b\[[0-9;]*m//g' | sed -n 's/^ *\(DEBUG\|WARN\) qml: //p'; }

gate_out="$(PROBE_MODE=gate run_probe gate "stealth/ox-alpha" "$OXALPHA_ENDPOINT")"
echo "$gate_out"
grep -q '^\[AI\] ai.extraModels\[1\] skipped' <<< "$gate_out" || fail "the malformed extraModels entry produced no warning naming index 1"
[[ ! -s "$WORK/xdg-gate/curl.log" ]] || { cat "$WORK/xdg-gate/curl.log" >&2; fail "a curl ran for a keyed model with no key"; }
echo "--- curl shim log (gate): $(wc -c < "$WORK/xdg-gate/curl.log") bytes"

# the header template the strategies emit, run through bash with and without a key
[[ "$(grep -c '^AUTH_TEMPLATE ' <<< "$gate_out")" == "2" ]] || fail "expected the probe to print two AUTH_TEMPLATE lines"
while read -r strategy template; do
    [[ -n "$template" ]] || fail "$strategy emitted an empty authorization template for a keyed model"
    empty="$(API_KEY="" bash -c "printf '%s\n' x $template" | tr '\n' ' ')"
    [[ "$empty" == "x " ]] || fail "$strategy: with an empty key bash expands the header to '$empty'"
    keyed="$(API_KEY="sk-test-fake" bash -c "printf '%s\n' x $template" | tr '\n' '|')"
    [[ "$keyed" == "x|-H|Authorization: Bearer sk-test-fake|" ]] || fail "$strategy: with a key bash expands the header to '$keyed'"
    echo "ok   $strategy header: nothing with an empty key, '-H' 'Authorization: Bearer <key>' with one"
done < <(sed -n 's/^AUTH_TEMPLATE //p' <<< "$gate_out")

retry_out="$(PROBE_MODE=retry run_probe retry "stealth/ox-alpha" "$OXALPHA_ENDPOINT")"
echo "$retry_out"
retry_log="$WORK/xdg-retry/curl.log"
[[ "$(wc -l < "$retry_log")" == "1" ]] || { cat "$retry_log" >&2; fail "expected exactly one curl after /key + retry, got $(wc -l < "$retry_log")"; }
grep -q -- "--max-time [0-9]* $OXALPHA_ENDPOINT " "$retry_log" || { cat "$retry_log" >&2; fail "the retried request did not go to $OXALPHA_ENDPOINT"; }
grep -q -- "-H Authorization: Bearer sk-test-fake " "$retry_log" || { cat "$retry_log" >&2; fail "the retried request did not carry the stored key"; }
grep -q '"model":"stealth/ox-alpha"' "$retry_log" || { cat "$retry_log" >&2; fail "the retried request body does not name the model"; }
grep -q 'hello without a key' "$retry_log" || { cat "$retry_log" >&2; fail "the retried request body does not carry the user's turn"; }
echo "--- curl shim log (retry): $(sed 's/\(Bearer sk-test-fake\).*/\1 .../' "$retry_log")"

echo "ok   key gate: no key -> advice, user turn kept, no curl; /key + retry -> one curl with the bearer; extraModels load with their fields, a malformed entry warns; windows: hosted 131072, local 8192, entry's context_window wins"
