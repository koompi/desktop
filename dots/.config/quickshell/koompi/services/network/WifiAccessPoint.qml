import QtQuick

QtObject {
    required property var lastIpcObject
    readonly property string ssid: lastIpcObject.ssid
    readonly property string bssid: lastIpcObject.bssid
    readonly property int strength: lastIpcObject.strength
    readonly property int frequency: lastIpcObject.frequency
    readonly property bool active: lastIpcObject.active
    readonly property string security: lastIpcObject.security
    readonly property bool isSecure: security.length > 0

    // NetworkManager's object path: the handle `connect` takes, because two radios can
    // broadcast the same ssid and only the path says which one was picked.
    readonly property string path: lastIpcObject.path ?? ""
    // The raw ssid bytes. An ssid is `ay` on the wire and is routinely not utf-8, so
    // this rather than `ssid` is what identity and dedupe belong on.
    readonly property string ssidHex: lastIpcObject.ssidHex ?? ""
    readonly property bool wantsPsk: lastIpcObject.wantsPsk ?? false
    readonly property bool enterprise: lastIpcObject.enterprise ?? false
    readonly property int bandGhz: lastIpcObject.bandGhz ?? 0

    property bool askingPassword: false
}
