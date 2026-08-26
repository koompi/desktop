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
    property var _deferred: null // the send waiting on the keyring

    // try_lookup.sh exits 2 on a locked keyring and KeyringStorage never flips
    // `loaded` for that, so a wait has an end or the user's message would sit
    // unanswered forever.
    property int keyringWaitMs: 10000

    // `loaded` and `keyringData` are set from two different signals of the fetch
    readonly property bool keyringReady: KeyringStorage.loaded && KeyringStorage.keyringData != null

    // True when the request may be built now. False when it was refused (advice
    // posted) or deferred: `send` runs by itself once the keyring reports in.
    function admit(model, send): bool {
        if (!model?.requires_key) return true;
        if (!root.keyringReady) {
            root._deferred = send;
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
    // keyring loads drops it; the user's turn stays in the transcript for a retry.
    function drop(reason: string) {
        if (!root._deferred) return;
        root._deferred = null;
        root.waitTimer.stop();
        console.log(`[AI] a send waiting on the keyring was dropped: ${reason}`);
    }

    // callLater: whichever of the two keyring signals came second has landed
    onKeyringReadyChanged: {
        if (!root.keyringReady || !root._deferred) return;
        const send = root._deferred;
        root._deferred = null;
        root.waitTimer.stop();
        Qt.callLater(send);
    }

    readonly property Connections modelWatch: Connections {
        target: root.engine
        ignoreUnknownSignals: true
        function onCurrentModelIdChanged() { root.drop("the model changed"); }
    }
    readonly property Connections chatWatch: Connections {
        target: root.engine?.conversation ?? null
        ignoreUnknownSignals: true
        function onMessageIDsChanged() {
            if (root.engine.conversation.messageIDs.length === 0) root.drop("the chat was cleared");
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
