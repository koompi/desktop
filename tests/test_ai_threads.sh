#!/usr/bin/env bash
# The AI thread store, run for real: a Quickshell process creates three threads
# in a temporary directory, writes a different conversation into each, throws the
# store away, rebuilds it from disk and reads all three back.
#
# Nothing here touches ~/.local/state/quickshell — the store's directory is a
# property and the probe points it at a temp dir.
set -uo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
SHELL_ROOT="$REPO_ROOT/dots/.config/quickshell/koompi"

[[ -f "$SHELL_ROOT/services/ai/ThreadStore.qml" ]] || {
    echo "missing services/ai/ThreadStore.qml" >&2; exit 1; }
[[ -f "$SHELL_ROOT/services/ai/Conversation.qml" ]] || {
    echo "missing services/ai/Conversation.qml" >&2; exit 1; }

# The store must never write outside its own directory: one reference, and it is
# the default of the property the probe below overrides.
refs="$(grep -c '^[^*]*Directories\.aiChats' "$SHELL_ROOT/services/ai/ThreadStore.qml")"
(( refs == 1 )) || {
    echo "ThreadStore names Directories.aiChats $refs times, expected 1" >&2; exit 1; }
grep -q '^ *property string directory: Directories\.aiChats' "$SHELL_ROOT/services/ai/ThreadStore.qml" || {
    echo "ThreadStore.directory is no longer an overridable property" >&2; exit 1; }

if ! command -v qs > /dev/null 2>&1; then
    echo "skip: quickshell (qs) not installed, static checks only"
    exit 0
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/shell" "$WORK/chats"

# A symlink farm rather than a copy: the real tree carries 378 MB of assets.
for entry in "$SHELL_ROOT"/*; do
    ln -s "$entry" "$WORK/shell/$(basename -- "$entry")"
done

cat > "$WORK/shell/threads_probe.qml" <<'QML'
import qs.services.ai
import Quickshell
import QtQuick

ShellRoot {
    id: probe

    property string dir: Quickshell.env("J03_CHATS_DIR")
    property int failures: 0

    function check(label, ok, detail) {
        console.log((ok ? "PASS " : "FAIL ") + label + (detail ? "  " + detail : ""));
        if (!ok) probe.failures++;
    }

    QtObject {
        id: fakeEngine
        property Component aiMessageComponent: Component { AiMessageData {} }
        property string interfaceRole: "interface"
        property var models: ({})
        property string currentModelId: ""
        property var postResponseHook: null
        property bool requestActive: false
        property string systemPrompt: ""
        property QtObject tokenCount: QtObject {
            property int input: -1
            property int output: -1
            property int total: -1
        }
        property QtObject requester: QtObject {
            property string lastSent: ""
            function sendUserMessage(text) { lastSent = text; }
        }
        function refreshSavedChats() {}
    }

    property Component conversationComponent: Component {
        Conversation {
            engine: fakeEngine
            chatsDirectory: probe.dir
        }
    }

    property var writer: null
    property var reader: null
    property var ids: []
    property var sessionIds: []

    Component.onCompleted: {
        probe.writer = probe.conversationComponent.createObject(probe);
        probe.writer.threadStore.refreshed.connect(probe.write);
    }

    function write() {
        const store = probe.writer.threadStore;
        probe.check("empty store starts empty", store.threads.length === 0,
            "threads=" + store.threads.length);

        for (let i = 1; i <= 3; i++) {
            const id = probe.writer.newThread();
            probe.ids.push(id);
            probe.writer.addMessage("question " + i + " about topic " + i, "user");
            probe.writer.addMessage("answer " + i + " for topic " + i, "assistant");
            probe.writer.saveChat("lastSession");
            probe.sessionIds.push(store.sessionId);
        }

        probe.check("three distinct thread ids",
            new Set(probe.ids).size === 3, JSON.stringify(probe.ids));
        probe.check("three distinct session ids",
            new Set(probe.sessionIds).size === 3, JSON.stringify(probe.sessionIds));
        probe.check("titles came from the first exchange",
            store.threads.every(t => t.title.indexOf("question ") === 0),
            JSON.stringify(store.threads.map(t => t.title)));

        // The save/load flush race: read back what was just written, same tick.
        const justSaved = store.readThread(probe.ids[2]);
        probe.check("save then load in one tick reads the new file",
            justSaved !== null && justSaved.messages.length === 2,
            "messages=" + (justSaved ? justSaved.messages.length : "null"));

        // A read that fails must not empty the conversation.
        const before = probe.writer.messageIDs.length;
        const missing = probe.writer.loadChat("no-such-thread");
        probe.check("a missing thread leaves the conversation alone",
            missing === false && probe.writer.messageIDs.length === before,
            "before=" + before + " after=" + probe.writer.messageIDs.length);

        probe.writer.renameThread(probe.ids[0], "renamed by hand");
        probe.subtask();

        // Throw the store away and rebuild it from the files on disk.
        probe.writer.destroy();
        probe.reader = probe.conversationComponent.createObject(probe);
        probe.reader.threadStore.refreshed.connect(probe.verify);
    }

    // D37: a subtask runs in its own Conversation, and a save while it runs
    // must write the user's thread, not the subtask's scratch context.
    function subtask() {
        const conv = probe.writer;
        const store = conv.threadStore;
        const id = store.currentThreadId;
        const mainCount = conv.messageIDs.length;

        conv.spawnSubtask("count the files in /etc");
        const sub = conv.subtaskConversation;
        probe.check("the subtask got its own Conversation",
            conv.inSubtask === true && sub !== null && sub.isSubtask === true,
            "inSubtask=" + conv.inSubtask);
        probe.check("the subtask starts from an empty context",
            conv.messageIDs.length === 1, "messages=" + conv.messageIDs.length);
        probe.check("the subtask prompt reached the requester",
            fakeEngine.requester.lastSent === "count the files in /etc",
            fakeEngine.requester.lastSent);

        conv.addMessage("there are 214 files in /etc", "assistant");
        conv.saveChat("lastSession");
        const onDisk = store.readThread(id);
        probe.check("a save during a subtask writes the user's thread, not the subtask",
            onDisk !== null && onDisk.messages.length === mainCount
                && !onDisk.messages.some(m => (m.rawContent ?? "").indexOf("214 files") >= 0),
            "stored=" + (onDisk ? onDisk.messages.length : "null") + " expected=" + mainCount);

        fakeEngine.postResponseHook();
        probe.check("the user's conversation came back",
            conv.inSubtask === false && conv.messageIDs.length === mainCount + 1,
            "messages=" + conv.messageIDs.length + " expected=" + (mainCount + 1));
        probe.check("the subtask result was reported",
            (conv.messageByID[conv.messageIDs[conv.messageIDs.length - 1]].rawContent ?? "")
                .indexOf("214 files") >= 0, "");
        probe.check("the subtask kept its own transcript",
            sub.messageIDs.length === 2, "subtaskMessages=" + sub.messageIDs.length);
    }

    function verify() {
        const store = probe.reader.threadStore;
        probe.check("all three threads survived the reload",
            store.threads.length === 3, "threads=" + store.threads.length);
        probe.check("the hand-typed title survived",
            store.threads.some(t => t.title === "renamed by hand"),
            JSON.stringify(store.threads.map(t => t.title)));

        for (let i = 0; i < 3; i++) {
            const id = probe.ids[i];
            const ok = probe.reader.loadChat(id);
            const texts = probe.reader.messageIDs.map(m => probe.reader.messageByID[m].rawContent);
            const n = i + 1;
            probe.check("thread " + n + " loads",
                ok === true && texts.length === 2, "messages=" + texts.length);
            probe.check("thread " + n + " kept its own content",
                texts.every(t => t.indexOf("topic " + n) >= 0), JSON.stringify(texts));
            probe.check("thread " + n + " kept its session id",
                store.sessionId === probe.sessionIds[i],
                store.sessionId + " vs " + probe.sessionIds[i]);
        }

        // Nothing crossed: every stored thread holds exactly its own topic.
        let crossed = 0;
        store.threads.forEach(t => {
            const data = store.readThread(t.id);
            const topics = new Set((data ? data.messages : []).map(
                m => (m.rawContent.match(/topic \d/) ?? ["?"])[0]));
            if (topics.size !== 1) crossed++;
        });
        probe.check("no thread holds another thread's messages", crossed === 0,
            "mixed=" + crossed);

        console.log(probe.failures === 0 ? "PROBE OK" : "PROBE FAILED " + probe.failures);
        Qt.callLater(() => Qt.quit());
    }
}
QML

out="$(J03_CHATS_DIR="$WORK/chats" timeout 120 qs -p "$WORK/shell/threads_probe.qml" 2>&1)"
echo "$out" | sed -n 's/.*qml\x1b\[0m: //p;s/^ DEBUG qml: //p' | grep -E '^(PASS|FAIL|PROBE)' || true

if ! grep -q "PROBE OK" <<< "$out"; then
    echo "--- probe output ---" >&2
    echo "$out" >&2
    exit 1
fi

files="$(ls -1 "$WORK/chats" | sort | tr '\n' ' ')"
count="$(ls -1 "$WORK/chats"/*.json 2>/dev/null | wc -l)"
(( count == 4 )) || { echo "expected 3 threads + index.json, got: $files" >&2; exit 1; }
[[ -f "$WORK/chats/index.json" ]] || { echo "no index.json written" >&2; exit 1; }

echo "ok: 3 threads created, reloaded from disk and read back without crossing"
