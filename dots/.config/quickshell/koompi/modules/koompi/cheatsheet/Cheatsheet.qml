import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt.labs.synchronizer
import Qt5Compat.GraphicalEffects
import Quickshell.Io
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland

Scope { // Scope
    id: root
    property var tabButtonList: [
        {
            "icon": "keyboard",
            "name": Translation.tr("Keybinds")
        },
        {
            "icon": "experiment",
            "name": Translation.tr("Elements")
        },
    ]

    function open() {
        GlobalStates.cheatsheetOpen = true;
    }

    function close() {
        GlobalStates.cheatsheetOpen = false;
    }

    function toggle() {
        GlobalStates.cheatsheetOpen = !GlobalStates.cheatsheetOpen;
    }

    // Persistent window, not a Loader: requesting keyboard focus made a per-open panel
    // slow to appear, and without it Escape and the page keys had no surface to reach.
    // A window that already exists is not mapped at open time.
    PanelWindow { // Window
        id: cheatsheetRoot
        visible: GlobalStates.cheatsheetOpen

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }

        exclusiveZone: 0
        implicitWidth: cheatsheetBackground.width + Appearance.sizes.elevationMargin * 2
        implicitHeight: cheatsheetBackground.height + Appearance.sizes.elevationMargin * 2
        WlrLayershell.namespace: "quickshell:cheatsheet"
        // OnDemand rather than Exclusive: since Hyprland 0.49 Exclusive breaks
        // click-outside-to-close, which the mask below depends on.
        WlrLayershell.keyboardFocus: GlobalStates.cheatsheetOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        color: "transparent"

        // Fullscreen window, but only the card takes input: a click beside it
        // reaches whatever is underneath, so the focus grab is the only thing
        // that can notice it.
        mask: Region {
            item: cheatsheetBackground
        }

        // Registration follows visibility rather than construction. The window
        // outlives a single open now, and a permanent entry in the dismissable
        // list would hold the shared grab active for the whole session.
        onVisibleChanged: {
            if (cheatsheetRoot.visible) {
                GlobalFocusGrab.addDismissable(cheatsheetRoot);
            } else {
                GlobalFocusGrab.removeDismissable(cheatsheetRoot);
            }
        }
        Connections {
            target: GlobalFocusGrab
            function onDismissed() {
                root.close();
            }
        }

        // Background
        StyledRectangularShadow {
            target: cheatsheetBackground
        }
        Rectangle {
            id: cheatsheetBackground
            anchors.centerIn: parent
            color: Appearance.colors.colLayer0
            border.width: 1
            // The outline carries the keyboard. `Window.active` is the surface's
            // own focus, not `cheatsheetOpen`: another panel opening on top takes
            // the keys while this one stays on screen.
            border.color: Window.active ? Appearance.colors.colPrimary : Appearance.colors.colLayer0Border
            radius: Appearance.rounding.windowRounding
            property real padding: 20
            implicitWidth: cheatsheetColumnLayout.implicitWidth + padding * 2
            implicitHeight: cheatsheetColumnLayout.implicitHeight + padding * 2

            Keys.onPressed: event => { // Esc to close
                if (event.key === Qt.Key_Escape) {
                    root.close();
                }
                if (event.modifiers === Qt.ControlModifier) {
                    if (event.key === Qt.Key_PageDown) {
                        tabBar.incrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_PageUp) {
                        tabBar.decrementCurrentIndex();
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Tab) {
                        tabBar.setCurrentIndex((tabBar.currentIndex + 1) % root.tabButtonList.length);
                        event.accepted = true;
                    } else if (event.key === Qt.Key_Backtab) {
                        tabBar.setCurrentIndex((tabBar.currentIndex - 1 + root.tabButtonList.length) % root.tabButtonList.length);
                        event.accepted = true;
                    }
                }
            }

            // Keyboard focus belongs to the search field in CheatsheetKeybinds,
            // which takes it on open; Escape and the tab chords bubble up here.
            RippleButton { // Close button
                id: closeButton
                implicitWidth: 40
                implicitHeight: 40
                buttonRadius: Appearance.rounding.full
                anchors {
                    top: parent.top
                    right: parent.right
                    topMargin: 20
                    rightMargin: 20
                }

                onClicked: {
                    root.close();
                }

                contentItem: MaterialSymbol {
                    anchors.centerIn: parent
                    horizontalAlignment: Text.AlignHCenter
                    font.pixelSize: Appearance.font.pixelSize.title
                    text: "close"
                }
            }

            ColumnLayout { // Real content
                id: cheatsheetColumnLayout
                anchors.centerIn: parent
                spacing: 10

                Toolbar {
                    Layout.alignment: Qt.AlignHCenter
                    enableShadow: false
                    ToolbarTabBar {
                        id: tabBar
                        tabButtonList: root.tabButtonList

                        Synchronizer on currentIndex {
                            property alias source: swipeView.currentIndex
                        }
                    }
                }

                SwipeView { // Content pages
                    id: swipeView
                    Layout.topMargin: 5
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 10
                    currentIndex: Persistent.states.cheatsheet.tabIndex
                    onCurrentIndexChanged: {
                        Persistent.states.cheatsheet.tabIndex = currentIndex;
                    }

                    implicitWidth: Math.max.apply(null, contentChildren.map(child => child.implicitWidth || 0))
                    implicitHeight: Math.max.apply(null, contentChildren.map(child => child.implicitHeight || 0))

                    clip: true
                    layer.enabled: true
                    layer.effect: OpacityMask {
                        maskSource: Rectangle {
                            width: swipeView.width
                            height: swipeView.height
                            radius: Appearance.rounding.small
                        }
                    }

                    CheatsheetKeybinds {}
                    CheatsheetPeriodicTable {}
                }
            }
        }
    }

    IpcHandler {
        target: "cheatsheet"

        function toggle(): void {
            root.toggle();
        }

        function close(): void {
            root.close();
        }

        function open(): void {
            root.open();
        }
    }

    GlobalShortcut {
        name: "cheatsheetToggle"
        description: "Toggles cheatsheet on press"

        onPressed: {
            root.toggle();
        }
    }

    GlobalShortcut {
        name: "cheatsheetOpen"
        description: "Opens cheatsheet on press"

        onPressed: {
            root.open();
        }
    }

    GlobalShortcut {
        name: "cheatsheetClose"
        description: "Closes cheatsheet on press"

        onPressed: {
            root.close();
        }
    }
}
