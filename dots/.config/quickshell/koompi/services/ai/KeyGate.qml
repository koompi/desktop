pragma ComponentBehavior: Bound

import qs.services
import QtQuick

/**
 * The gate in front of every curl the Requester and the compactor build. A model
 * that needs a key goes out only when the keyring has loaded and holds one; a
 * missing key answers with the /key advice instead of a request carrying an empty
 * bearer. A keyring that has not loaded yet is "unknown", not "missing": the send
 * waits for it. `engine` is the Ai facade.
 */
QtObject {
    id: root

    property QtObject engine
    // what waits on the keyring: { send, kind ("send" | "compact"), modelId }
    property var _deferred: null

    // try_lookup.sh exits 2 on a locked keyring and KeyringStorage never flips
    // `loaded` for that, so a wait has an end or the user's message would sit
    // unanswered forever.
    property int keyringWaitMs: 10000

    // `loaded` and `keyringData` are set from two different signals of the fetch
    readonly property bool keyringReady: KeyringStorage.loaded && KeyringStorage.keyringData != null

    // True when the request may be built now. False when it was refused (advice
    // posted) or deferred: `send` runs by itself once the keyring reports in.
    // One slot: a waiting send is never displaced by a compaction (that one is
    // skipped; the turn decides again after it), a waiting compaction is
    // displaced by a send.
    function admit(model, send, kind = "send"): bool {
        if (!model?.requires_key) return true;
        if (!root.keyringReady) {
            if (kind === "compact" && root._deferred?.kind === "send") {
                console.log("[AI] compaction skipped: a message is already waiting on the keyring");
                return false;
            }
            root._deferred = { "send": send, "kind": kind, "modelId": root.engine.currentModelId };
            root.waitTimer.restart();
            KeyringStorage.fetchKeyringData();
            return false;
        }
        const key = root.engine.apiKeys?.[model.key_id] ?? "";
        if (key.length > 0) return true;
        root.engine.addApiKeyAdvice(model);
        return false;
    }

    // The wait was for this model and this chat. A switch or a clear while the
    // keyring loads drops it, and says so: the user's turn stays in the transcript
    // for a retry, and nothing else is going to answer it.
    function take() {
        const waiting = root._deferred;
        root._deferred = null;
        root.waitTimer.stop();
        return waiting;
    }
    function drop(reason: string) {
        const waiting = root.take();
        if (waiting) root.note(waiting, reason);
    }
    function note(waiting, reason: string) {
        root.engine.addMessage(waiting.kind === "compact"
            ? Translation.tr("Compaction skipped: %1 before the keyring answered.").arg(reason)
            : Translation.tr("Your message was not sent: %1 before the keyring answered. Send it again.").arg(reason),
            root.engine.interfaceRole);
    }

    // callLater: whichever of the two keyring signals came second has landed
    onKeyringReadyChanged: {
        if (!root.keyringReady || !root._deferred) return;
        const send = root._deferred.send;
        root._deferred = null;
        root.waitTimer.stop();
        Qt.callLater(send);
    }

    // Ai.currentModelId is a var forwarded over `models`, which is reassigned by
    // discovery and by the config reload; the signal fires with the same value
    // then, so the wait is dropped only when the id really differs.
    readonly property Connections modelWatch: Connections {
        target: root.engine
        ignoreUnknownSignals: true
        function onCurrentModelIdChanged() {
            if (root._deferred && root.engine.currentModelId !== root._deferred.modelId) root.drop(Translation.tr("the model changed"));
        }
    }
    // The ids empty before the map does in clearMessages, so the slot is freed
    // here and the note is appended once the clear has finished.
    readonly property Connections chatWatch: Connections {
        target: root.engine?.conversation ?? null
        ignoreUnknownSignals: true
        function onMessageIDsChanged() {
            if (root.engine.conversation.messageIDs.length !== 0 || !root._deferred) return;
            const waiting = root.take();
            Qt.callLater(() => root.note(waiting, Translation.tr("the chat was cleared")));
        }
    }

    readonly property Timer waitTimer: Timer {
        interval: root.keyringWaitMs
        repeat: false
        onTriggered: {
            if (!root._deferred) return;
            root._deferred = null;
            root.engine.addMessage(
                Translation.tr("The keyring did not answer, so the API key could not be read and the message was not sent. Unlock the keyring and retry."),
                root.engine.interfaceRole);
        }
    }
}
