pragma ComponentBehavior: Bound
import qs.modules.common
import qs.modules.common.widgets
import qs.services
import qs.modules.koompi.sidebarRight.calendar
import qs.modules.koompi.sidebarRight.todo
import qs.modules.koompi.sidebarRight.pomodoro
import QtQuick
import QtQuick.Layouts

ColumnLayout {
    id: root
    spacing: Appearance.spacing.normal
    property int previousIndex: -1
    property var tabs: [
        {
            "type": "calendar",
            "name": Translation.tr("Calendar"),
            "icon": "calendar_month",
            "widget": "calendar/CalendarWidget.qml"
        },
        {
            "type": "todo",
            "name": Translation.tr("To Do"),
            "icon": "done_outline",
            "widget": "todo/TodoWidget.qml"
        },
        {
            "type": "timer",
            "name": Translation.tr("Timer"),
            "icon": "schedule",
            "widget": "pomodoro/PomodoroWidget.qml"
        },
    ]

    Keys.onPressed: event => {
        if ((event.key === Qt.Key_PageDown || event.key === Qt.Key_PageUp) && event.modifiers === Qt.ControlModifier) {
            if (event.key === Qt.Key_PageDown) {
                tabBar.currentIndex = Math.min(tabBar.currentIndex + 1, root.tabs.length - 1);
            } else if (event.key === Qt.Key_PageUp) {
                tabBar.currentIndex = Math.max(tabBar.currentIndex - 1, 0);
            }
            event.accepted = true;
        }
    }

    // Second tab row, under Today/Personal. Leaves the body full width.
    SecondaryTabBar {
        id: tabBar
        Component.onCompleted: currentIndex = Persistent.states.sidebar.bottomGroup.tab
        onCurrentIndexChanged: Persistent.states.sidebar.bottomGroup.tab = currentIndex
        Repeater {
            model: root.tabs
            delegate: SecondaryTabButton {
                required property var modelData
                buttonText: modelData.name
                buttonIcon: modelData.icon
            }
        }
    }

    Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: Appearance.rounding.normal
        color: Appearance.colors.colLayer1
        clip: true

        // One Loader, so only the selected tool exists.
        Loader {
            id: tabStack
            anchors.fill: parent
            anchors.bottomMargin: -anchors.topMargin

            Component.onCompleted: {
                tabStack.source = root.tabs[tabBar.currentIndex].widget;
            }

            Connections {
                target: tabBar
                function onCurrentIndexChanged() {
                    tabSwitchBehavior.animation.down = tabBar.currentIndex > root.previousIndex;
                    tabStack.source = root.tabs[tabBar.currentIndex].widget;
                }
            }

            Behavior on source {
                id: tabSwitchBehavior
                animation: TabSwitchAnim {
                    id: upAnim
                    down: true
                }
            }
        }
    }

    component TabSwitchAnim: SequentialAnimation {
        id: switchAnim
        property bool down: false
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
            PropertyAnimation {
                target: tabStack.anchors
                properties: "topMargin"
                to: 10 * (switchAnim.down ? -1 : 1)
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveFast.bezierCurve
            }
        }
        PropertyAction {
            target: tabStack
            property: "source"
            value: root.tabs[tabBar.currentIndex].widget
        } // The source change happens here
        ParallelAnimation {
            PropertyAnimation {
                target: tabStack.anchors
                properties: "topMargin"
                from: 10 * -(switchAnim.down ? -1 : 1)
                to: 0
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
            PropertyAnimation {
                target: tabStack
                properties: "opacity"
                to: 1
                duration: Appearance.animation.elementMoveFast.duration
                easing.type: Easing.BezierSpline
                easing.bezierCurve: Appearance.animation.elementMoveEnter.bezierCurve
            }
        }
        ScriptAction {
            script: {
                root.previousIndex = tabBar.currentIndex;
            }
        }
    }
}
