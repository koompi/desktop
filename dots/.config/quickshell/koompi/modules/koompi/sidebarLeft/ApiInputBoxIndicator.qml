import qs.modules.common
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Layouts

Item { // Model indicator
    id: root
    property string icon: "api"
    property string text: ""
    property string tooltipText: ""
    property var onClickedAction: null
    signal clicked()
    implicitHeight: rowLayout.implicitHeight + 4 * 2
    implicitWidth: rowLayout.implicitWidth + 4 * 2

    RowLayout {
        id: rowLayout
        anchors.centerIn: parent

        MaterialSymbol {
            text: root.icon
            iconSize: Appearance.font.pixelSize.normal
        }
        StyledText {
            id: providerName
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: Appearance.m3colors.m3onSurface
            elide: Text.ElideRight
            text: root.text
            animateChange: true
        }
    }

    Loader {
        active: root.tooltipText?.length > 0 || root.onClickedAction !== null
        anchors.fill: parent
        sourceComponent: MouseArea {
            id: mouseArea
            hoverEnabled: true
            cursorShape: root.onClickedAction ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                root.clicked();
                if (root.onClickedAction) root.onClickedAction();
            }

            StyledToolTip {
                id: toolTip
                extraVisibleCondition: false
                alternativeVisibleCondition: mouseArea.containsMouse // Show tooltip when hovered
                text: root.tooltipText
            }
        }
    }
}
