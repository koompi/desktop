pragma ComponentBehavior: Bound

import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts

// One source a turn actually used: what kind it is, how well it matched, what it
// is, and one line saying where in it the claim came from.
RippleButton {
    id: root
    property string sourceType: "web"
    property string name: ""
    property string detail: ""
    property real score: NaN
    property string url: ""
    property bool flashing: false

    readonly property bool openable: root.url.length > 0
    readonly property string typeLabel: root.sourceType.toUpperCase()
    readonly property string scoreLabel: isFinite(root.score) ? root.score.toFixed(2) : ""

    readonly property color badgeColor: {
        switch (root.sourceType) {
        case "web": return Appearance.colors.colPrimaryContainer;
        case "file": return Appearance.colors.colSecondaryContainer;
        case "memory": return Appearance.colors.colTertiaryContainer;
        default: return Appearance.colors.colSurfaceContainerHighest;
        }
    }
    readonly property color onBadgeColor: {
        switch (root.sourceType) {
        case "web": return Appearance.colors.colOnPrimaryContainer;
        case "file": return Appearance.colors.colOnSecondaryContainer;
        case "memory": return Appearance.colors.colOnTertiaryContainer;
        default: return Appearance.colors.colOnSurface;
        }
    }

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + 12
    buttonRadius: Appearance.rounding.small
    colBackground: root.flashing ? Appearance.colors.colLayer2Active : Appearance.colors.colLayer2
    colBackgroundHover: Appearance.colors.colLayer2Hover
    colRipple: Appearance.colors.colLayer2Active
    pointingHandCursor: root.openable
    focusPolicy: Qt.StrongFocus
    activeFocusOnTab: true

    Accessible.role: Accessible.Button
    Accessible.name: Translation.tr("Source %1, match %2: %3. %4")
        .arg(root.typeLabel).arg(root.scoreLabel.length > 0 ? root.scoreLabel : Translation.tr("unscored"))
        .arg(root.name).arg(root.detail)

    onClicked: {
        if (!root.openable) return;
        Qt.openUrlExternally(root.url)
        GlobalStates.sidebarLeftOpen = false
    }

    Rectangle { // focus ring
        anchors.fill: parent
        radius: Appearance.rounding.small
        color: "transparent"
        border.width: root.activeFocus ? 2 : 0
        border.color: Appearance.colors.colPrimary
    }

    contentItem: RowLayout {
        id: rowLayout
        spacing: 8

        Rectangle {
            Layout.alignment: Qt.AlignTop
            Layout.topMargin: 2
            implicitWidth: badgeText.implicitWidth + 12
            implicitHeight: badgeText.implicitHeight + 4
            radius: Appearance.rounding.verysmall
            color: root.badgeColor

            StyledText {
                id: badgeText
                anchors.centerIn: parent
                text: root.scoreLabel.length > 0 ? `${root.typeLabel} · ${root.scoreLabel}` : root.typeLabel
                font.pixelSize: Appearance.font.pixelSize.smallest
                font.weight: Font.DemiBold
                color: root.onBadgeColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 1

            StyledText {
                Layout.fillWidth: true
                text: root.name
                elide: Text.ElideRight
                maximumLineCount: 1
                font.pixelSize: Appearance.font.pixelSize.smaller
                font.weight: Font.DemiBold
                color: Appearance.colors.colOnLayer2
            }

            StyledText {
                Layout.fillWidth: true
                visible: root.detail.length > 0
                text: root.detail
                elide: Text.ElideRight
                maximumLineCount: 2
                wrapMode: Text.Wrap
                font.pixelSize: Appearance.font.pixelSize.smallest
                color: Appearance.colors.colSubtext
            }
        }

        // J09 hangs the per-source "This is wrong" control here.
        Item {
            objectName: "correctionSlot"
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: 0
            implicitHeight: 0
        }

        MaterialSymbol {
            visible: root.openable
            Layout.alignment: Qt.AlignVCenter
            text: "open_in_new"
            iconSize: Appearance.font.pixelSize.normal
            color: Appearance.colors.colSubtext
        }
    }
}
