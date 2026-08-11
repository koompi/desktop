#!/usr/bin/env bash
# End to end against whatever is actually on this machine: the LiteRT-LM server,
# the memory daemon, the request body on disk, and the threads the shell has
# written. Every other test in this directory shadows the commands that would
# touch the machine; this one is the opposite, and it is the only one that can
# tell you the assistant works here rather than in principle.
#
# A machine without the backend or the daemon skips the parts that need them and
# still runs the ones that do not, so the suite stays green on a build box.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

fail() { echo "FAIL: $1" >&2; exit 1; }
skip() { echo "  skip: $1"; }
ok()   { echo "  ok: $1"; }

need() { command -v "$1" >/dev/null 2>&1; }

PORT="$(sed -n 's/.*property int litertPort: \([0-9]*\).*/\1/p' "$SHELL_ROOT/modules/common/Config.qml" | head -1)"
PORT="${PORT:-9379}"
BASE="http://127.0.0.1:${PORT}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/quickshell/ai"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/user/ai"
MEMD="$(sed -n 's/.*\(\.local\/bin\/koompi-agent-memd\).*/\1/p' "$SHELL_ROOT/services/MemoryService.qml" | head -1)"
MEMD="$HOME/${MEMD:-.local/bin/koompi-agent-memd}"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

# ---------------------------------------------------------------- the backend

backend_up=0
if need curl && curl -sf -m 5 -o "$TMP/models.json" "$BASE/v1/models"; then
    backend_up=1
    ok "backend answers $BASE/v1/models"
else
    skip "no LiteRT-LM on $BASE — backend assertions not run"
fi

if (( backend_up )); then
    # The shell's model picker is built from this list. An empty one leaves the
    # user with no local model at all and the panel silently falls back to remote.
    if need jq; then
        count="$(jq -r '.data | length' "$TMP/models.json" 2>/dev/null)"
        [[ "${count:-0}" =~ ^[0-9]+$ ]] && (( count > 0 )) \
            || fail "$BASE/v1/models answered but listed no models"
        ok "model list has $count model(s): $(jq -r '[.data[].id] | join(", ")' "$TMP/models.json")"
    else
        grep -q '"id"' "$TMP/models.json" || fail "$BASE/v1/models listed no models"
        ok "model list is non-empty"
    fi

    # The discovery script the shell actually runs, not a hand-rolled curl.
    disco="$SHELL_ROOT/scripts/ai/show-installed-litert-lm-models.sh"
    if [[ -x "$disco" ]] || [[ -f "$disco" ]]; then
        out="$(bash "$disco" 2>/dev/null)"
        [[ "$out" == "["*"]" ]] || fail "show-installed-litert-lm-models.sh did not emit a JSON array: $out"
        [[ "$out" != "[]" ]] || fail "show-installed-litert-lm-models.sh found no models while $BASE answers"
        ok "the shell's own discovery script returns $out"
    fi
fi

# ------------------------------------------------------------- the memory daemon

if [[ -x "$MEMD" ]]; then
    printf '%s\n' '{"id":1,"op":"ping"}' '{"id":2,"op":"stats"}' \
        | timeout 60 "$MEMD" > "$TMP/memd.out" 2>"$TMP/memd.err"
    rc=$?
    (( rc == 0 )) || fail "$MEMD exited $rc: $(head -3 "$TMP/memd.err")"

    # The banner is the line with a version and no request behind it; `ready` in
    # MemoryService keys off exactly that.
    grep -q '"version"' "$TMP/memd.out" || fail "memd never printed its ready banner"
    ok "memd banner: $(head -1 "$TMP/memd.out")"

    grep -q '"id":1,"ok":true' "$TMP/memd.out" || fail "memd did not answer ping: $(cat "$TMP/memd.out")"
    ok "memd answered ping"

    stats="$(grep '"id":2' "$TMP/memd.out")"
    [[ "$stats" == *'"ok":true'* ]] || fail "memd did not answer stats: $stats"
    [[ "$stats" == *'"count"'* ]]  || fail "memd stats carried no count: $stats"
    ok "memd answered stats: $stats"
else
    skip "no $MEMD — memory assertions not run"
fi

# --------------------------------------------------- the request body on disk

# The body is the whole conversation. It used to land in shared /tmp at 0644.
if [[ -d "$RUNTIME_DIR" ]]; then
    mode="$(stat -c '%a' "$RUNTIME_DIR")"
    [[ "$mode" == "700" ]] || fail "$RUNTIME_DIR is mode $mode, expected 700"
    ok "$RUNTIME_DIR is 0700"

    for f in request.sh compact.sh; do
        [[ -f "$RUNTIME_DIR/$f" ]] || continue
        fmode="$(stat -c '%a' "$RUNTIME_DIR/$f")"
        [[ "$fmode" == "600" ]] || fail "$RUNTIME_DIR/$f is mode $fmode, expected 600"
        ok "$RUNTIME_DIR/$f is 0600"
    done
else
    skip "no $RUNTIME_DIR — the shell has not sent a request on this boot"
fi

# The narrowing is done by the wrapper the shell execs, so run that exact wrapper
# over a file left wide open and assert it closes before bash ever reads it.
wrapper="$(grep -o "chmod 600 \"\$1\" 2>/dev/null; exec bash \"\$1\"" \
    "$SHELL_ROOT/services/ai/Requester.qml" | head -1)"
[[ -n "$wrapper" ]] || fail "Requester.qml no longer chmods the request script before exec"
probe="$TMP/probe.sh"
printf '#!/usr/bin/env bash\nstat -c %%a "$0"\n' > "$probe"
chmod 644 "$probe"
seen="$(bash -c "$wrapper" -- "$probe")"
[[ "$seen" == "600" ]] || fail "the wrapper left the request script at $seen when curl read it"
ok "the wrapper narrows the script to 0600 before the body is readable"

# ------------------------------------------------ no orphaned curl after a cancel

# The original hang held the server's only inference slot. `exec` is what makes
# killing the shell kill curl; without it a bash wrapper dies and curl keeps the
# slot. Assert the property on the real command shape.
grep -q 'exec curl --no-buffer --max-time' "$SHELL_ROOT/services/ai/Requester.qml" \
    || fail "the request script no longer execs curl with a --max-time"

if (( backend_up )); then
    script="$TMP/req.sh"
    # A request big enough to still be streaming when the cancel lands.
    body="$(printf '{"model":"%s","messages":[{"role":"user","content":"Write a 400 word essay about rivers."}],"stream":true}' \
        "$(need jq && jq -r '.data[0].id' "$TMP/models.json" || echo gemma4-e2b)")"
    printf '#!/usr/bin/env bash\nexec curl --no-buffer --max-time 180 "%s/v1/chat/completions" -H '\''Content-Type: application/json'\'' --data '\''%s'\''\n' \
        "$BASE" "$body" > "$script"
    curls() { pgrep -fc "curl --no-buffer" 2>/dev/null | head -1 || true; }
    before="$(curls)"; before="${before:-0}"
    bash -c 'chmod 600 "$1" 2>/dev/null; exec bash "$1"' -- "$script" >/dev/null 2>&1 &
    top=$!
    sleep 3
    kill "$top" 2>/dev/null
    wait "$top" 2>/dev/null
    sleep 2
    after="$(curls)"; after="${after:-0}"
    (( after <= before )) || fail "a cancelled request left $((after - before)) curl process(es) behind"
    ok "no curl survived the cancel"

    # And the slot it held is free: the next request answers.
    if ! curl -sf -m 60 -o /dev/null "$BASE/v1/models"; then
        fail "the server stopped answering after a cancelled request"
    fi
    ok "the server's inference slot is free after the cancel"
fi

# ------------------------------------------------ threads survive a shell reload

# A reload re-reads these files and nothing else. If the index and the thread
# files agree on disk, the conversation the user was in comes back.
if [[ -f "$STATE_DIR/chats/index.json" ]] && need jq; then
    idx="$STATE_DIR/chats/index.json"
    jq -e 'type == "object" and (.threads | type == "array")' "$idx" >/dev/null \
        || fail "$idx is not a thread index"

    current="$(jq -r '.current // ""' "$idx")"
    [[ -n "$current" ]] || fail "$idx names no current thread, so a reload has nothing to resume"

    while read -r id mc; do
        file="$STATE_DIR/chats/$id.json"
        [[ -f "$file" ]] || fail "index lists thread '$id' but $file does not exist"
        jq -e '.' "$file" >/dev/null 2>&1 || fail "$file is not readable JSON; a reload would open an empty chat"
        onDisk="$(jq -r 'if type == "array" then length else (.messages | length) end' "$file")"
        (( onDisk == mc )) || fail "thread '$id': index says $mc messages, the file holds $onDisk"
    done < <(jq -r '.threads[] | "\(.id) \(.messageCount)"' "$idx")
    ok "every thread in the index resolves to a readable file with a matching message count"

    # `lastSession` is an alias, resolved to the last active thread. A reload that
    # cannot resolve it opens a blank conversation over the user's chat.
    if [[ "$current" == "lastSession" ]]; then
        [[ -f "$STATE_DIR/chats/lastSession.json" ]] \
            || fail "current is the lastSession alias but no lastSession.json exists to resolve it to"
    fi
    ok "current thread '$current' resolves"
else
    skip "no thread index at $STATE_DIR/chats — the shell has never saved a chat here"
fi

# ---------------------------------------------------------------- the deadline

# The value the user sees on a hung turn comes from here; a floor of 10 stops a
# stray 0 in the config from turning every request into an instant failure.
grep -q 'Math.max(10, Config.options?.ai?.requestTimeoutSec' "$SHELL_ROOT/services/ai/Requester.qml" \
    || fail "the request deadline is no longer floored"
grep -q 'and the model.s slot freed' "$SHELL_ROOT/services/ai/Requester.qml" \
    || fail "a timed-out turn no longer tells the user the slot was freed"
ok "a turn has a floored deadline and says so when it expires"

echo "test_ai_e2e: all assertions passed"
