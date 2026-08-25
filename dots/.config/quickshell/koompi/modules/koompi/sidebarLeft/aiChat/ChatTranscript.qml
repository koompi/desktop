import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft
import qs.modules.koompi.sidebarLeft.aiChat.composer
import QtQuick
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell

// The message list with its status bar, empty-state starters and the stall
// watchdog. It never touches the composer: focus and text go out as signals.
Item {
    id: root
    property real padding: 4
    property bool composerEmpty: true
    // Forwarded to every AiMessage; the composer this transcript pairs with.
    property var messageInputField: null
    property bool stallDetected: false

    signal starterChosen(string text)
    signal settingsRequested()
    signal composerFocusRequested()

    // True when the transcript took focus; false when there is nothing to focus.
    function focusTranscript() {
        if (messageListView.count === 0)
            return false;
        messageListView.currentIndex = messageListView.count - 1;
        messageListView.positionViewAtEnd();
        messageListView.forceActiveFocus(Qt.TabFocusReason);
        return true;
    }

    function positionAtEnd() {
        messageListView.positionViewAtEnd();
    }

    function positionAtBeginning() {
        messageListView.positionViewAtBeginning();
    }

    function pageUp() {
        messageListView.contentY = Math.max(0, messageListView.contentY - messageListView.height / 2);
    }

    function pageDown() {
        messageListView.contentY = Math.min(messageListView.contentHeight - messageListView.height / 2, messageListView.contentY + messageListView.height / 2);
    }

    Timer {
        id: stallWatchdog
        interval: 60000
        repeat: false
        onTriggered: { if (Ai.requestActive) root.stallDetected = true }
    }

    Connections {
        target: Ai
        function onTokenStreamed() { stallWatchdog.restart(); root.stallDetected = false }
        function onResponseFinished() { stallWatchdog.stop(); root.stallDetected = false }
        function onRequestActiveChanged() {
            if (Ai.requestActive) { stallWatchdog.restart() }
            else { stallWatchdog.stop(); root.stallDetected = false }
        }
    }

    layer.enabled: true
    layer.effect: OpacityMask {
        maskSource: Rectangle {
            width: root.width
            height: root.height
            radius: Appearance.rounding.small
        }
    }

    StyledRectangularShadow {
        z: 1
        target: statusBg
        opacity: messageListView.atYBeginning ? 0 : 1
        visible: opacity > 0
        Behavior on opacity {
            animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
        }
    }
    Rectangle {
        id: statusBg
        z: 2
        anchors {
            horizontalCenter: parent.horizontalCenter
            top: parent.top
            topMargin: 4
        }
        implicitWidth: Math.min(parent.width - 8, statusBar.implicitWidth + 10 * 2)
        implicitHeight: Math.max(statusBar.implicitHeight + 6 * 2, 38)
        radius: Appearance.rounding.normal - root.padding
        color: messageListView.atYBeginning ? Appearance.colors.colLayer2 : Appearance.colors.colLayer2Base
        Behavior on color {
            animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
        }
        Behavior on implicitHeight {
            animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
        }

        ChatStatusBar {
            id: statusBar
            anchors.centerIn: parent
            width: parent.width - 10 * 2
            stalled: root.stallDetected
            active: root.visible
            onStopRequested: {
                Ai.cancelRequest();
                root.stallDetected = false;
            }
            onRetryRequested: {
                Ai.retryRequest();
                root.stallDetected = false;
            }
            onSettingsRequested: root.settingsRequested()
        }
    }

    ScrollEdgeFade {
        z: 1
        target: messageListView
        vertical: true
    }

    StyledListView { // Message list
        id: messageListView
        z: 0
        anchors.fill: parent
        spacing: 10
        popin: false
        topMargin: statusBg.implicitHeight + statusBg.anchors.topMargin * 2
        scrollAnimation: false
        activeFocusOnTab: true

        touchpadScrollFactor: Config.options.interactions.scrolling.touchpadScrollFactor * 1.4
        mouseScrollFactor: Config.options.interactions.scrolling.mouseScrollFactor * 1.4

        property int lastResponseLength: 0
        // A new message (user or AI) always jumps the view to the newest one,
        // so the user never has to scroll down to see the latest chat.
        onCountChanged: Qt.callLater(positionViewAtEnd)
        // While a response streams in, keep the bottom pinned — but only if the
        // user is already at the bottom, so scrolling up to read isn't yanked back.
        onContentHeightChanged: {
            if (atYEnd)
                Qt.callLater(positionViewAtEnd);
        }

        Keys.onPressed: event => {
            if (event.key === Qt.Key_Escape || event.key === Qt.Key_Backtab) {
                root.composerFocusRequested();
                event.accepted = true;
            }
        }

        add: null // Prevent function calls from being janky

        model: ScriptModel {
            values: Ai.messageIDs.filter(id => {
                const message = Ai.messageByID[id];
                return message?.visibleToUser ?? true;
            })
        }
        delegate: AiMessage {
            required property var modelData
            required property int index
            messageIndex: index
            messageData: Ai.messageByID[modelData]
            messageInputField: root.messageInputField
        }
    }

    PagePlaceholder {
        z: 2
        shown: Ai.messageIDs.length === 0
        icon: "auto_awesome"
        title: Translation.tr("Ask about this computer")
        description: Translation.tr("I read and change your settings,\nrun a command when you say yes,\nlook things up, and send an agent\nto inspect this machine.\n\nIt runs here. No key, no network.")
        descriptionHorizontalAlignment: Text.AlignHCenter
        shape: MaterialShape.Shape.PixelCircle
    }

    ColumnLayout { // Empty-state starters
        z: 2
        visible: Ai.messageIDs.length === 0 && root.composerEmpty
        anchors {
            left: parent.left
            right: parent.right
            bottom: parent.bottom
            leftMargin: 20
            rightMargin: 20
            bottomMargin: 20
        }
        spacing: 5

        Repeater {
            // Every starter has to finish on the local model with no key and
            // no network, so none of them may reach for ask_agent.
            model: [
                Translation.tr("What can you do on this computer?"),
                Translation.tr("Run df -h and tell me how full my disk is"),
                Translation.tr("Is my bar at the top or the bottom?")
            ]
            delegate: ApiCommandButton {
                id: starterButton
                required property string modelData
                Layout.fillWidth: true
                buttonText: starterButton.modelData
                Accessible.name: starterButton.modelData
                onClicked: root.starterChosen(starterButton.modelData)
            }
        }
    }

    ScrollToBottomButton {
        z: 3
        target: messageListView
    }
}
