import qs.services
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.sidebarLeft
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

/**
 * What is answering, whether it can be reached, how full the context is and
 * whether memory is running - plus the one action that fixes whatever is wrong.
 */
ColumnLayout {
    id: root

    property bool stalled: false
    property bool active: true
    signal stopRequested()
    signal retryRequested()
    signal modelPickerRequested()
    signal keyRequested()

    readonly property var currentModel: Ai.getModel()
    readonly property string endpoint: root.currentModel?.endpoint ?? ""
    readonly property bool onThisMachine: root.endpoint.includes("127.0.0.1") || root.endpoint.includes("localhost") || root.endpoint.includes("[::1]")
    readonly property string modelName: {
        const code = root.currentModel?.model ?? "";
        return code.length > 0 ? code : (root.currentModel?.name ?? Translation.tr("No model"));
    }
    readonly property bool needsKey: (root.currentModel?.requires_key ?? false) && !Ai.currentModelHasApiKey
    readonly property string host: {
        const match = root.endpoint.match(/^[a-z]+:\/\/([^/]+)/);
        return match ? match[1] : root.endpoint;
    }
    readonly property string probeUrl: root.endpoint.replace(/\/chat\/completions.*$/, "/models")

    // "" while nothing has been measured yet: an unprobed backend is not a broken one.
    property string reachable: ""
    property int probeFailures: 0

    readonly property int contextWindow: Math.max(1, Ai.contextWindow)
    readonly property real contextFill: Math.max(0, Ai.tokenCount.total) / root.contextWindow
    readonly property bool memoryOn: MemoryService.ready

    readonly property string trouble: {
        if (root.stalled)
            return "stalled";
        if (root.onThisMachine && root.reachable === "no")
            return "unreachable";
        if (root.needsKey)
            return "nokey";
        return "";
    }

    spacing: 2

    function probeNow() {
        // LiteRT-LM answers one request at a time, so probing mid-turn would queue
        // behind the answer and read as a failure.
        if (!root.active || !root.onThisMachine || Ai.requestActive || backendProbe.running)
            return;
        backendProbe.running = true;
    }

    Process {
        id: backendProbe
        command: ["curl", "-sf", "-o", "/dev/null", "-m", "4", root.probeUrl]
        onExited: exitCode => {
            if (exitCode === 0) {
                root.probeFailures = 0;
                root.reachable = "yes";
            } else {
                root.probeFailures += 1;
                if (root.probeFailures >= 2)
                    root.reachable = "no";
            }
        }
    }

    Process {
        id: restartBackend
        command: ["systemctl", "--user", "restart", "litert-lm"]
        onExited: {
            root.probeFailures = 0;
            root.reachable = "";
            probeTimer.restart();
        }
    }

    Timer {
        id: probeTimer
        interval: 15000
        repeat: true
        running: root.active && root.onThisMachine
        triggeredOnStart: true
        onTriggered: root.probeNow()
    }

    Connections {
        target: Ai
        function onRequestActiveChanged() {
            if (Ai.requestActive) {
                // A turn in flight is proof the backend answered.
                root.probeFailures = 0;
                root.reachable = "yes";
            } else {
                probeTimer.restart();
            }
        }
    }

    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 8

        Rectangle { // Reachability
            implicitWidth: 8
            implicitHeight: 8
            radius: width / 2
            color: root.stalled ? Appearance.m3colors.m3tertiary
                 : root.trouble.length > 0 ? Appearance.colors.colError
                 : root.reachable === "yes" ? Appearance.colors.colPrimary
                 : Appearance.colors.colOutlineVariant
            Behavior on color {
                animation: Appearance.animation.elementMoveFast.colorAnimation.createObject(this)
            }

            MouseArea {
                id: healthArea
                anchors.fill: parent
                anchors.margins: -6
                hoverEnabled: true
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: healthArea.containsMouse
                    text: root.stalled ? Translation.tr("Answering, but nothing has arrived for a minute")
                        : root.reachable === "yes" ? Translation.tr("Answering from %1").arg(root.host)
                        : root.reachable === "no" ? Translation.tr("Nothing is listening on %1").arg(root.host)
                        : Translation.tr("Not checked yet")
                }
            }
        }

        MaterialSymbol {
            text: root.onThisMachine ? "computer" : "cloud"
            iconSize: Appearance.font.pixelSize.large
            color: Appearance.colors.colSubtext
        }

        StyledText {
            id: modelText
            Layout.maximumWidth: 160
            font.pixelSize: Appearance.font.pixelSize.small
            color: Appearance.colors.colOnLayer2
            elide: Text.ElideRight
            text: root.modelName

            MouseArea {
                id: modelArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.modelPickerRequested()
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: modelArea.containsMouse
                    text: (root.onThisMachine
                            ? Translation.tr("Runs on this machine. Nothing you type leaves it.")
                            : Translation.tr("Runs on someone else's machine. What you type is sent there."))
                        + "\n" + root.endpoint
                        + "\n" + Translation.tr("Click to switch model")
                }
            }
        }

        Rectangle { // separator
            implicitWidth: 4
            implicitHeight: 4
            radius: width / 2
            color: Appearance.colors.colOutlineVariant
            visible: contextText.visible
        }

        StyledText {
            id: contextText
            visible: Ai.tokenCount.total > 0
            font.pixelSize: Appearance.font.pixelSize.small
            color: root.contextFill >= 0.85 ? Appearance.colors.colError
                 : root.contextFill >= 0.60 ? Appearance.m3colors.m3tertiary
                 : Appearance.colors.colSubtext
            text: Translation.tr("%1% full").arg(Math.round(root.contextFill * 100))

            MouseArea {
                id: contextArea
                anchors.fill: parent
                hoverEnabled: true
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: contextArea.containsMouse
                    text: Translation.tr("%1 of %2 tokens used\nInput %3 - output %4\nOlder turns are summarised past %5")
                        .arg(Ai.tokenCount.total).arg(root.contextWindow)
                        .arg(Ai.tokenCount.input).arg(Ai.tokenCount.output)
                        .arg(Ai.compactionThreshold)
                }
            }
        }

        Rectangle { // separator
            implicitWidth: 4
            implicitHeight: 4
            radius: width / 2
            color: Appearance.colors.colOutlineVariant
        }

        MaterialSymbol {
            id: memoryIcon
            text: root.memoryOn ? "database" : "database_off"
            iconSize: Appearance.font.pixelSize.large
            color: root.memoryOn ? Appearance.colors.colSubtext : Appearance.colors.colOutlineVariant

            MouseArea {
                id: memoryArea
                anchors.fill: parent
                hoverEnabled: true
                StyledToolTip {
                    extraVisibleCondition: false
                    alternativeVisibleCondition: memoryArea.containsMouse
                    text: root.memoryOn
                        ? Translation.tr("Remembering across sessions")
                        : Translation.tr("Not remembering: koompi-agent-memd is not running")
                }
            }
        }
    }

    RowLayout { // What is wrong, and what fixes it
        id: troubleRow
        Layout.fillWidth: true
        Layout.alignment: Qt.AlignHCenter
        visible: root.trouble.length > 0
        spacing: 5

        StyledText {
            Layout.fillWidth: true
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.colors.colError
            wrapMode: Text.Wrap
            horizontalAlignment: Text.AlignHCenter
            text: root.trouble === "stalled" ? Translation.tr("No answer for a minute")
                : root.trouble === "unreachable" ? Translation.tr("Nothing is listening on %1").arg(root.host)
                : Translation.tr("%1 needs an API key").arg(root.modelName)
        }

        ApiCommandButton {
            visible: root.trouble === "stalled"
            buttonText: Translation.tr("Stop")
            onClicked: root.stopRequested()
        }
        ApiCommandButton {
            visible: root.trouble === "stalled"
            buttonText: Translation.tr("Retry")
            onClicked: root.retryRequested()
        }
        ApiCommandButton {
            visible: (root.trouble === "unreachable" || root.trouble === "stalled") && root.onThisMachine
            buttonText: restartBackend.running ? Translation.tr("Restarting…") : Translation.tr("Restart it")
            onClicked: {
                if (!restartBackend.running)
                    restartBackend.running = true;
            }
            StyledToolTip {
                text: Translation.tr("systemctl --user restart litert-lm")
            }
        }
        ApiCommandButton {
            visible: root.trouble === "nokey"
            buttonText: Translation.tr("Set key")
            onClicked: root.keyRequested()
            StyledToolTip {
                text: Translation.tr("Puts /key in the composer. The key is stored in the keyring, not in a file.")
            }
        }
    }
}
