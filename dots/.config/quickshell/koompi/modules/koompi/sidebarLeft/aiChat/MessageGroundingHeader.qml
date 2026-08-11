pragma ComponentBehavior: Bound

import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// Who answered, from where, and how much of the answer is held up by something
// other than the model's own weights. The number is the grounding computed in
// grounding.js; when nothing backed the turn it says exactly that instead of
// putting a percentage on a guess.
ColumnLayout {
    id: root
    property string modelId: ""
    property bool usedAgent: false
    property var grounding: null

    readonly property var modelInfo: Ai.models?.[root.modelId] ?? null
    readonly property string modelName: (root.modelInfo?.name ?? root.modelId) || Translation.tr("unknown model")
    readonly property string endpoint: root.modelInfo?.endpoint ?? ""
    readonly property bool onThisMachine: /(\/\/|^)(127\.0\.0\.1|localhost|0\.0\.0\.0|\[::1\])/.test(root.endpoint)
    // An unknown model gets no locality claim rather than a wrong one.
    readonly property string locality: root.usedAgent ? Translation.tr("escalated agent")
        : root.endpoint.length === 0 ? ""
        : root.onThisMachine ? Translation.tr("local")
        : Translation.tr("remote")
    readonly property string identity: root.locality.length > 0
        ? Translation.tr("KOOMPI AI · %1 · %2").arg(root.locality).arg(root.modelName)
        : Translation.tr("KOOMPI AI · %1").arg(root.modelName)

    readonly property real value: root.grounding?.value ?? -1
    readonly property string band: root.grounding?.band ?? "none"
    readonly property color bandColor: {
        switch (root.band) {
        case "grounded": return Appearance.colors.colPrimary;
        case "partial": return Appearance.colors.colSecondary;
        case "guessing": return Appearance.colors.colError;
        default: return Appearance.colors.colOutline;
        }
    }
    readonly property color chipColor: {
        switch (root.band) {
        case "grounded": return Appearance.colors.colPrimaryContainer;
        case "partial": return Appearance.colors.colSecondaryContainer;
        case "guessing": return Appearance.colors.colErrorContainer;
        default: return Appearance.colors.colSurfaceContainerHighest;
        }
    }
    readonly property color onChipColor: {
        switch (root.band) {
        case "grounded": return Appearance.colors.colOnPrimaryContainer;
        case "partial": return Appearance.colors.colOnSecondaryContainer;
        case "guessing": return Appearance.colors.colOnErrorContainer;
        default: return Appearance.colors.colSubtext;
        }
    }
    readonly property string chipText: {
        switch (root.band) {
        case "grounded": return Translation.tr("Grounding %1% - traced").arg(Math.round(root.value * 100));
        case "partial": return Translation.tr("Grounding %1% - not sure").arg(Math.round(root.value * 100));
        case "guessing": return Translation.tr("Grounding %1% - guessing").arg(Math.round(root.value * 100));
        default: return Translation.tr("Nothing backed this answer");
        }
    }

    spacing: 4

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        MaterialSymbol {
            text: "auto_awesome"
            iconSize: Appearance.font.pixelSize.smallie
            color: Appearance.colors.colOnLayer1
        }

        StyledText {
            Layout.fillWidth: true
            elide: Text.ElideRight
            maximumLineCount: 1
            text: root.identity
            font.pixelSize: Appearance.font.pixelSize.smallest
            font.weight: Font.DemiBold
            color: Appearance.colors.colOnLayer1
        }

        Rectangle {
            // StyledToolTip reads `hovered` off its parent, so the chip needs one.
            property bool hovered: chipHover.hovered
            implicitWidth: chipLabel.implicitWidth + 14
            implicitHeight: chipLabel.implicitHeight + 4
            radius: Appearance.rounding.full
            color: root.chipColor

            HoverHandler { id: chipHover }

            Accessible.role: Accessible.StaticText
            Accessible.name: root.chipText

            StyledText {
                id: chipLabel
                anchors.centerIn: parent
                text: root.chipText
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: root.onChipColor
            }

            StyledToolTip {
                text: root.grounding
                    ? Translation.tr("Computed from what the turn used: %1").arg(root.grounding.basis)
                    : Translation.tr("No source, no retrieval and no tool backed this turn, so there is no grounding to report.")
            }
        }
    }

    Item { // Calibration band. A meter, not a vibe - and absent when unmeasurable.
        Layout.fillWidth: true
        visible: root.grounding !== null
        implicitHeight: visible ? 12 : 0

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.right: parent.right
            implicitHeight: 4
            radius: height / 2
            color: Appearance.colors.colSurfaceContainerHighest

            Rectangle {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * Math.max(0, Math.min(1, root.value))
                height: parent.height
                radius: height / 2
                color: root.bandColor

                Behavior on width {
                    animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
                }
            }
        }

        Rectangle {
            anchors.verticalCenter: track.verticalCenter
            x: track.width * Math.max(0, Math.min(1, root.value)) - width / 2
            implicitWidth: 10
            implicitHeight: 10
            radius: width / 2
            color: Appearance.colors.colLayer1
            border.width: 2
            border.color: root.bandColor

            Behavior on x {
                animation: Appearance.animation.elementResize.numberAnimation.createObject(this)
            }
        }
    }
}
