pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell

// The sources a turn used, one row each. A turn that used none renders nothing
// at all - an empty citation block reads as "checked and found nothing", which
// is a stronger claim than the turn earns.
ColumnLayout {
    id: root
    property var sources: []
    property int highlightedIndex: -1

    readonly property int count: root.sources?.length ?? 0
    readonly property bool anyRemote: (root.sources ?? []).some(s => s?.type === "web")

    function highlight(index) {
        root.highlightedIndex = index;
        highlightTimer.restart();
    }

    Timer {
        id: highlightTimer
        interval: Appearance.animationDuration.slowest
        onTriggered: root.highlightedIndex = -1
    }

    visible: root.count > 0
    spacing: 3

    StyledText {
        Layout.topMargin: 4
        text: Translation.tr("Sources (%1)").arg(root.count)
        font.pixelSize: Appearance.font.pixelSize.smallest
        font.weight: Font.DemiBold
        color: Appearance.colors.colSubtext
    }

    Repeater {
        model: ScriptModel {
            values: root.sources ?? []
        }

        MessageSourceRow {
            required property var modelData
            required property int index
            sourceType: modelData?.type ?? "web"
            name: modelData?.name ?? ""
            detail: modelData?.detail ?? ""
            score: Number(modelData?.score)
            url: modelData?.url ?? ""
            flashing: root.highlightedIndex === index
        }
    }

    RowLayout { // Locality footer: whether answering this cost the user privacy
        Layout.fillWidth: true
        Layout.topMargin: 2
        spacing: 4

        MaterialSymbol {
            text: root.anyRemote ? "public" : "lock"
            iconSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }

        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            text: root.anyRemote
                ? Translation.tr("A web source was fetched, so this turn left the machine.")
                : Translation.tr("Every source is on this machine. Nothing left it.")
            font.pixelSize: Appearance.font.pixelSize.smallest
            color: Appearance.colors.colSubtext
        }
    }
}
