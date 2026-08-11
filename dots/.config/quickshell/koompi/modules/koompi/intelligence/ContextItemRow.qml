pragma ComponentBehavior: Bound

import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.koompi.intelligence
import QtQuick
import QtQuick.Layouts

// One thing the next request will carry: what kind it is, what it costs, one
// line of what it says, and the control that takes it back out.
Rectangle {
    id: root

    property var item: null

    signal dropRequested
    signal restoreRequested

    readonly property string typeLabel: String(root.item?.type ?? "").toUpperCase()
    readonly property bool dropped: root.item?.dropped ?? false
    readonly property bool droppable: root.item?.droppable ?? false
    readonly property int tokens: IntelligenceContext.tokensFor(root.item?.chars ?? 0)
    readonly property string scoreLabel: isFinite(root.item?.score ?? NaN) ? Number(root.item.score).toFixed(2) : ""

    readonly property color badgeColor: {
        switch (root.item?.type) {
        case "web":
            return Appearance.colors.colPrimaryContainer;
        case "file":
            return Appearance.colors.colSecondaryContainer;
        case "memory":
            return Appearance.colors.colTertiaryContainer;
        case "agent":
            return Appearance.colors.colErrorContainer;
        default:
            return Appearance.colors.colSurfaceContainerHighest;
        }
    }
    readonly property color onBadgeColor: {
        switch (root.item?.type) {
        case "web":
            return Appearance.colors.colOnPrimaryContainer;
        case "file":
            return Appearance.colors.colOnSecondaryContainer;
        case "memory":
            return Appearance.colors.colOnTertiaryContainer;
        case "agent":
            return Appearance.colors.colOnErrorContainer;
        default:
            return Appearance.colors.colOnSurface;
        }
    }

    implicitHeight: rowLayout.implicitHeight + Appearance.spacing.normal * 2
    radius: Appearance.rounding.small
    color: Appearance.colors.colLayer2
    opacity: root.dropped ? 0.55 : 1

    Behavior on opacity {
        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
    }

    Accessible.role: Accessible.ListItem
    Accessible.name: Translation.tr("%1 source: %2, %3 tokens%4").arg(root.typeLabel).arg(root.item?.name ?? "").arg(root.tokens).arg(root.dropped ? Translation.tr(", held out of the next turn") : "")

    RowLayout {
        id: rowLayout
        anchors {
            fill: parent
            margins: Appearance.spacing.normal
        }
        spacing: Appearance.spacing.normal

        Rectangle { // type badge
            Layout.alignment: Qt.AlignTop
            implicitWidth: badgeText.implicitWidth + Appearance.spacing.normal
            implicitHeight: badgeText.implicitHeight + Appearance.spacing.small
            radius: Appearance.rounding.verysmall
            color: root.badgeColor

            StyledText {
                id: badgeText
                anchors.centerIn: parent
                text: root.typeLabel
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                font.letterSpacing: 1
                color: root.onBadgeColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: Appearance.spacing.hairline

            StyledText {
                Layout.fillWidth: true
                text: root.item?.name ?? ""
                font.pixelSize: Appearance.font.pixelSize.small
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                font.strikeout: root.dropped
            }

            StyledText {
                Layout.fillWidth: true
                text: root.item?.detail ?? ""
                font.pixelSize: Appearance.font.pixelSize.smaller
                color: Appearance.colors.colSubtext
                elide: Text.ElideRight
            }

            StyledText {
                visible: (root.item?.excerpt ?? "").length > 0
                Layout.fillWidth: true
                text: root.item.excerpt
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.monospace
                color: Appearance.colors.colOnLayer2
                elide: Text.ElideRight
                maximumLineCount: 1
            }
        }

        ColumnLayout {
            Layout.alignment: Qt.AlignTop
            spacing: Appearance.spacing.hairline

            StyledText {
                Layout.alignment: Qt.AlignRight
                text: root.dropped ? Translation.tr("held out") : Translation.tr("%1 tok").arg(root.tokens)
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.family: Appearance.font.family.numbers
                color: root.dropped ? Appearance.colors.colError : Appearance.colors.colOnLayer2
            }

            StyledText {
                visible: root.scoreLabel.length > 0
                Layout.alignment: Qt.AlignRight
                text: Translation.tr("match %1").arg(root.scoreLabel)
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        IconToolbarButton {
            visible: root.droppable
            Layout.fillHeight: false
            Layout.alignment: Qt.AlignTop
            implicitHeight: 30
            text: root.dropped ? "undo" : "block"
            colText: root.dropped ? Appearance.colors.colOnLayer2 : Appearance.colors.colError
            onClicked: {
                if (root.dropped)
                    root.restoreRequested();
                else
                    root.dropRequested();
            }
            Accessible.name: root.dropped ? Translation.tr("Put it back") : Translation.tr("Drop from the next turn")
            StyledToolTip {
                text: root.dropped ? Translation.tr("Send this again with the next turn") : Translation.tr("Keep this out of the next request")
            }
        }
    }
}
