pragma ComponentBehavior: Bound

import qs
import qs.modules.common
import qs.modules.common.widgets
import qs.modules.koompi.intelligence
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

/**
 * Master-detail, the same shape the settings window uses: a rail that expands
 * past a width threshold, a content pane that cross-fades. Built when the window
 * opens and destroyed when it closes, so nothing here costs anything while the
 * assistant is not on screen.
 */
FocusScope {
    id: root

    readonly property var panes: [
        {
            "icon": "forum",
            "name": Translation.tr("Chat")
        },
        {
            "icon": "history",
            "name": Translation.tr("Threads")
        },
        {
            "icon": "neurology",
            "name": Translation.tr("Memory")
        },
        {
            "icon": "bolt",
            "name": Translation.tr("Activity")
        },
        {
            "icon": "database",
            "name": Translation.tr("Active Context")
        },
    ]

    // Two-way, not a binding: the first write from here would break a binding and
    // the panes could no longer be driven from outside the window - which is what
    // the IPC and a pane resuming a thread both do.
    property int currentPane: 0
    onCurrentPaneChanged: IntelligenceContext.currentPane = root.currentPane

    Connections {
        target: IntelligenceContext
        function onCurrentPaneChanged() {
            root.currentPane = IntelligenceContext.currentPane;
        }
    }

    // 0 follows the width, anything else is the user overruling it.
    property int railOverride: 0
    readonly property int railWidthThreshold: 900
    readonly property bool railExpanded: root.railOverride === 0 ? root.width > root.railWidthThreshold : root.railOverride > 0

    readonly property real contentPadding: Appearance.spacing.normal

    function goToPane(index) {
        root.currentPane = Math.max(0, Math.min(index, root.panes.length - 1));
    }

    function stepPane(delta) {
        root.goToPane((root.currentPane + delta + root.panes.length) % root.panes.length);
    }

    Component.onCompleted: {
        root.currentPane = Math.min(IntelligenceContext.currentPane, root.panes.length - 1);
        console.log("[intelligence] content built");
    }
    Component.onDestruction: console.log("[intelligence] content destroyed")

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Escape) {
            GlobalStates.intelligenceOpen = false;
            event.accepted = true;
            return;
        }
        if (event.modifiers & Qt.ControlModifier) {
            if (event.key === Qt.Key_Tab || event.key === Qt.Key_PageDown) {
                root.stepPane(1);
                event.accepted = true;
            } else if (event.key === Qt.Key_Backtab || event.key === Qt.Key_PageUp) {
                root.stepPane(-1);
                event.accepted = true;
            } else if (event.key === Qt.Key_B) {
                root.railOverride = root.railExpanded ? -1 : 1;
                event.accepted = true;
            } else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_5) {
                // Ctrl, not Alt: Hyprland binds Alt and Super plus a number to
                // workspaces, and the compositor wins that race every time.
                root.goToPane(event.key - Qt.Key_1);
                event.accepted = true;
            }
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Appearance.colors.colLayer0

        ColumnLayout {
            anchors {
                fill: parent
                margins: root.contentPadding
            }
            spacing: root.contentPadding

            RowLayout { // titlebar
                Layout.fillWidth: true
                spacing: Appearance.spacing.small

                RippleButton {
                    implicitWidth: 35
                    implicitHeight: 35
                    buttonRadius: Appearance.rounding.full
                    onClicked: root.railOverride = root.railExpanded ? -1 : 1
                    Accessible.name: Translation.tr("Toggle the navigation rail")

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        iconSize: 20
                        color: Appearance.colors.colOnLayer0
                        text: root.railExpanded ? "menu_open" : "menu"
                    }

                    StyledToolTip {
                        text: Translation.tr("Collapse or expand the rail (Ctrl+B)")
                    }
                }

                StyledText {
                    text: Translation.tr("Intelligence")
                    color: Appearance.colors.colOnLayer0
                    font {
                        family: Appearance.font.family.title
                        pixelSize: Appearance.font.pixelSize.title
                        variableAxes: Appearance.font.variableAxes.title
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: Appearance.spacing.small
                    text: Ai.threadTitle && Ai.threadTitle.length > 0 ? Ai.threadTitle : Translation.tr("New conversation")
                    color: Appearance.colors.colSubtext
                    font.pixelSize: Appearance.font.pixelSize.small
                    elide: Text.ElideRight
                }

                ModelChip {}

                RippleButton {
                    implicitWidth: 35
                    implicitHeight: 35
                    buttonRadius: Appearance.rounding.full
                    // The inverse of the sidebar's open_in_full. Both surfaces
                    // drive the same engine, so the thread is already there.
                    onClicked: {
                        GlobalStates.intelligenceOpen = false;
                        GlobalStates.sidebarLeftOpen = true;
                    }
                    Accessible.name: Translation.tr("Back to the sidebar")

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close_fullscreen"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer0
                    }

                    StyledToolTip {
                        text: Translation.tr("Back to the sidebar")
                    }
                }

                RippleButton {
                    implicitWidth: 35
                    implicitHeight: 35
                    buttonRadius: Appearance.rounding.full
                    onClicked: GlobalStates.intelligenceOpen = false
                    Accessible.name: Translation.tr("Close")

                    contentItem: MaterialSymbol {
                        anchors.centerIn: parent
                        horizontalAlignment: Text.AlignHCenter
                        text: "close"
                        iconSize: 20
                        color: Appearance.colors.colOnLayer0
                    }
                }
            }

            RowLayout { // rail and content
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: root.contentPadding

                Item {
                    id: navRailWrapper
                    Layout.fillHeight: true
                    implicitWidth: root.railExpanded ? 190 : 56

                    Behavior on implicitWidth {
                        animation: Appearance.animation.elementMoveFast.numberAnimation.createObject(this)
                    }

                    NavigationRail {
                        id: navRail
                        anchors {
                            left: parent.left
                            top: parent.top
                            bottom: parent.bottom
                        }
                        spacing: Appearance.spacing.normal
                        expanded: root.railExpanded

                        NavigationRailTabArray {
                            id: navTabs
                            currentIndex: root.currentPane
                            expanded: root.railExpanded

                            Repeater {
                                model: root.panes

                                NavigationRailButton {
                                    required property var index
                                    required property var modelData
                                    toggled: root.currentPane === index
                                    onPressed: root.goToPane(index)
                                    expanded: root.railExpanded
                                    buttonIcon: modelData.icon
                                    buttonText: modelData.name
                                    showToggledHighlight: false
                                    showCollapsedLabel: false
                                    Accessible.name: modelData.name
                                }
                            }
                        }

                        Item {
                            Layout.fillHeight: true
                        }

                        ContextBudgetBar {
                            Layout.fillWidth: true
                            Layout.bottomMargin: Appearance.spacing.normal
                            compact: !root.railExpanded
                        }
                    }
                }

                Rectangle { // content container
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    color: Appearance.m3colors.m3surfaceContainerLow
                    radius: Appearance.rounding.normal

                    Loader {
                        id: paneLoader
                        anchors.fill: parent
                        anchors.margins: root.contentPadding
                        opacity: 1.0
                        sourceComponent: root.componentFor(root.currentPane)

                        Connections {
                            target: root
                            function onCurrentPaneChanged() {
                                switchAnim.complete();
                                switchAnim.start();
                            }
                        }

                        SequentialAnimation {
                            id: switchAnim

                            NumberAnimation {
                                target: paneLoader
                                properties: "opacity"
                                from: 1
                                to: 0
                                duration: Appearance.animation.elementMoveExit.duration
                                easing.type: Appearance.animation.elementMoveExit.type
                                easing.bezierCurve: Appearance.animation.elementMoveExit.bezierCurve
                            }
                            PropertyAction {
                                target: paneLoader
                                property: "sourceComponent"
                                value: root.componentFor(root.currentPane)
                            }
                            NumberAnimation {
                                target: paneLoader
                                properties: "opacity"
                                from: 0
                                to: 1
                                duration: Appearance.animation.elementMoveEnter.duration
                                easing.type: Appearance.animation.elementMoveEnter.type
                                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
                            }
                        }
                    }
                }
            }
        }
    }

    function componentFor(index) {
        switch (index) {
        case 1:
            return threadsPaneComponent;
        case 2:
            return memoryPaneComponent;
        case 3:
            return activityPaneComponent;
        case 4:
            return activeContextPaneComponent;
        default:
            return chatPaneComponent;
        }
    }

    Component {
        id: chatPaneComponent
        ChatPane {}
    }
    Component {
        id: threadsPaneComponent
        ThreadsPane {}
    }
    Component {
        id: memoryPaneComponent
        MemoryPane {}
    }
    Component {
        id: activityPaneComponent
        ActivityPane {}
    }
    Component {
        id: activeContextPaneComponent
        ActiveContextPane {}
    }
}
