import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft
import QtQuick
import QtQuick.Layouts

// Recall-while-typing strip (#13): memories that match what is being typed,
// debounced, until the user dismisses it for this message.
ColumnLayout {
    id: root
    property string prefix: "/"
    property var results: []
    property bool shown: false
    property bool dismissed: false
    property string typed: ""

    visible: root.shown
    spacing: 2

    // Call from the composer on every text change.
    function noteTyping(text) {
        root.typed = text;
        if (text.length === 0) {
            root.dismissed = false;
        }
        if (text.length >= 3 && !text.startsWith(root.prefix)) {
            debounce.restart();
        } else {
            debounce.stop();
            root.results = [];
            root.shown = false;
        }
    }

    // Call when a message is sent: a dismissal only lasts for one message.
    function reset() {
        root.dismissed = false;
    }

    Timer {
        id: debounce
        interval: 600
        repeat: false
        onTriggered: {
            const text = root.typed;
            if (text.length < 3 || text.startsWith(root.prefix) || !MemoryService.ready) {
                root.results = [];
                root.shown = false;
                return;
            }
            MemoryService.recall(text, 3, results => {
                root.results = results ?? [];
                root.shown = !root.dismissed && root.results.length > 0;
            });
        }
    }

    RowLayout {
        Layout.fillWidth: true
        StyledText {
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: Translation.tr("Recalled:")
        }
        Item { Layout.fillWidth: true }
        ApiCommandButton {
            contentItem: StyledText {
                font.pixelSize: Appearance.font.pixelSize.small
                color: Appearance.m3colors.m3onSurface
                text: "×"
            }
            onClicked: {
                root.shown = false;
                root.dismissed = true;
            }
        }
    }
    Repeater {
        model: root.results.slice(0, 3)
        delegate: StyledText {
            required property var modelData
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colSubtext
            text: "• " + (modelData.text ?? "")
            wrapMode: Text.WordWrap
            elide: Text.ElideRight
            maximumLineCount: 2
        }
    }
}
