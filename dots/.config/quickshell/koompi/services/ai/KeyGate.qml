pragma ComponentBehavior: Bound

import qs.services
import QtQuick

/**
 * The gate in front of every curl the Requester builds. A model that needs a key
 * goes out only when the keyring has loaded and holds one; a missing key answers
 * with the /key advice instead of a request carrying an empty bearer. A keyring
 * that has not loaded yet is "unknown", not "missing": the send waits for it.
 * `engine` is the Ai facade.
 */
QtObject {
    id: root

    property QtObject engine
    property var _deferred: null // the send waiting on the keyring

    // try_lookup.sh exits 2 on a locked keyring and KeyringStorage never flips
    // `loaded` for that, so a wait has an end or the user's message would sit
    // unanswered forever.
    property int keyringWaitMs: 10000

    // True when the request may be built now. False when it was refused (advice
    // posted) or deferred: `send` runs by itself once the keyring reports in.
    function admit(model, send): bool {
        if (!model?.requires_key) return true;
        if (!root.engine.apiKeysLoaded) {
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

    readonly property Connections keyringWatch: Connections {
        target: KeyringStorage
        function onLoadedChanged() {
            if (!KeyringStorage.loaded || !root._deferred) return;
            const send = root._deferred;
            root._deferred = null;
            root.waitTimer.stop();
            send();
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
