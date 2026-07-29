pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import qs.modules.common
import qs.modules.common.widgets

// A desktop command row dedicated to the global menu. This intentionally does
// not inherit RippleButton: shell buttons and application menus have different
// density, alignment, selection, and motion requirements.
Item {
    id: root

    required property var entry
    required property var menu
    property bool keyHighlighted: false

    readonly property bool isSeparator: entry.sep ?? false
    readonly property bool hasChildren: menu.hasChildrenFor(entry)
    readonly property bool showsToggle: entry.toggle ?? false
    readonly property bool selected: !isSeparator && enabled && (hoverHandler.hovered || keyHighlighted)
    readonly property color selectionColor: Appearance.m3colors.darkmode ? "#34775e" : "#277858"
    readonly property color foregroundColor: selected ? "#ffffff" : Appearance.colors.colOnLayer0
    readonly property color secondaryColor: selected ? Qt.rgba(1, 1, 1, 0.78) : Appearance.colors.colSubtext

    signal triggered
    signal openChildren
    signal entered

    enabled: !isSeparator && (entry.enabled ?? true)
    opacity: enabled || isSeparator ? 1 : 0.42
    implicitHeight: isSeparator ? 9 : 30
    implicitWidth: contentRow.implicitWidth + 16

    Rectangle {
        anchors {
            fill: parent
            leftMargin: 4
            rightMargin: 4
            topMargin: 1
            bottomMargin: 1
        }
        visible: root.selected
        radius: 6
        color: root.selectionColor

        Behavior on color {
            ColorAnimation {
                duration: 70
            }
        }
    }

    Rectangle {
        visible: root.isSeparator
        anchors {
            left: parent.left
            right: parent.right
            verticalCenter: parent.verticalCenter
            leftMargin: 26
            rightMargin: 8
        }
        height: 1
        color: Appearance.m3colors.darkmode
            ? Qt.rgba(1, 1, 1, 0.13)
            : Qt.rgba(0, 0, 0, 0.12)
    }

    HoverHandler {
        id: hoverHandler
        enabled: root.enabled && !root.isSeparator
        onHoveredChanged: if (hovered)
            root.entered()
    }

    TapHandler {
        enabled: root.enabled && !root.isSeparator
        acceptedButtons: Qt.LeftButton
        onTapped: {
            if (root.hasChildren)
                root.openChildren();
            else
                root.triggered();
        }
    }

    RowLayout {
        id: contentRow
        anchors {
            verticalCenter: parent.verticalCenter
            left: parent.left
            right: parent.right
            leftMargin: 10
            rightMargin: 10
        }
        spacing: 3
        visible: !root.isSeparator

        Item {
            implicitWidth: 14
            implicitHeight: 16

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.showsToggle && (root.entry.checked ?? false)
                text: "check"
                iconSize: 15
                color: root.foregroundColor
            }
        }

        StyledText {
            Layout.fillWidth: true
            text: root.entry.label ?? ""
            font.pixelSize: Appearance.font.pixelSize.smallie
            font.weight: Font.Normal
            color: root.foregroundColor
            elide: Text.ElideRight
        }

        StyledText {
            visible: (root.entry.shortcut ?? "").length > 0
            text: root.entry.shortcut ?? ""
            font.pixelSize: Appearance.font.pixelSize.smaller
            color: root.secondaryColor
        }

        Item {
            implicitWidth: 12
            implicitHeight: 16

            MaterialSymbol {
                anchors.centerIn: parent
                visible: root.hasChildren
                text: "chevron_right"
                iconSize: 15
                color: root.secondaryColor
            }
        }
    }
}
