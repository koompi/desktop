import qs
import qs.services
import qs.modules.common
import qs.modules.common.widgets
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import "steps.js" as Steps

/**
 * The whole desktop, one step at a time, for someone who has never used Linux.
 *
 * Separate from the welcome guide on purpose: FirstRunGuide caps at four steps
 * because 20260730-first-run-guide criterion 2 says so, and growing it into this
 * would break an assignment in review.
 */
Scope {
    id: root

    readonly property var steps: Steps.steps
    property int index: 0
    readonly property var step: root.steps[Math.min(root.index, root.steps.length - 1)]

    // The flag a step asked to be opened, remembered so it can be closed again
    // whatever ends the step - Next, Back, Escape or the shortcut.
    property string openedDemo: ""

    function applyDemo(name) {
        if (root.openedDemo === name)
            return;
        if (root.openedDemo.length > 0)
            GlobalStates[root.openedDemo] = false;
        root.openedDemo = name ?? "";
        if (root.openedDemo.length > 0)
            GlobalStates[root.openedDemo] = true;
    }

    function go(delta) {
        const next = root.index + delta;
        if (next < 0)
            return;
        if (next >= root.steps.length) {
            root.close();
            return;
        }
        root.index = next;
        root.applyDemo(root.steps[next].demo);
    }

    function open() {
        root.index = 0;
        GlobalStates.tourOpen = true;
        root.applyDemo(root.steps[0].demo);
    }

    function close() {
        // Criterion 7: leave the desktop as it was found.
        root.applyDemo("");
        GlobalStates.tourOpen = false;
    }

    function toggle() {
        if (GlobalStates.tourOpen)
            root.close();
        else
            root.open();
    }

    PanelWindow {
        id: tourWindow
        visible: GlobalStates.tourOpen
        color: "transparent"

        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusiveZone: 0
        WlrLayershell.namespace: "quickshell:tour"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: GlobalStates.tourOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Only the card takes input, so the surface a step just opened is still
        // clickable underneath it.
        mask: Region {
            item: card
        }

        // Persistent, not dismissable: nearly every surface a step opens is
        // itself dismissable and would take the shared grab, closing the tour
        // the moment it demonstrated anything. Same reason the bar uses it.
        onVisibleChanged: {
            if (tourWindow.visible)
                GlobalFocusGrab.addPersistent(tourWindow);
            else
                GlobalFocusGrab.removePersistent(tourWindow);
        }

        StyledRectangularShadow {
            target: card
        }

        Rectangle {
            id: card

            // Keys belong on the card and focus on a child inside it: a
            // PanelWindow is not in the focus chain, so a handler up there
            // never sees an event. Cheatsheet.qml is the reference.
            // Return and Space are left to the focused button below rather
            // than handled here, or one press would advance twice.
            Keys.onPressed: event => {
                if (event.key === Qt.Key_Escape) {
                    root.close();
                    event.accepted = true;
                } else if (event.key === Qt.Key_Right) {
                    root.go(1);
                    event.accepted = true;
                } else if (event.key === Qt.Key_Left) {
                    root.go(-1);
                    event.accepted = true;
                }
            }
            // Low and to one side, so the surface each step opens stays visible.
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: Appearance.sizes.elevationMargin + 40
            implicitWidth: 460
            implicitHeight: content.implicitHeight + 32
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.normal
            border.width: 1
            border.color: Appearance.colors.colLayer0Border

            ColumnLayout {
                id: content
                anchors.centerIn: parent
                width: parent.width - 32
                spacing: 10

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    MaterialSymbol {
                        text: root.step?.icon ?? ""
                        iconSize: Appearance.font.pixelSize.larger
                        color: Appearance.m3colors.m3primary
                    }
                    StyledText {
                        Layout.fillWidth: true
                        text: Translation.tr(root.step?.title ?? "")
                        font.pixelSize: Appearance.font.pixelSize.large
                        font.weight: Font.DemiBold
                    }
                    StyledText {
                        text: `${root.index + 1}/${root.steps.length}`
                        color: Appearance.m3colors.m3outline
                        font.pixelSize: Appearance.font.pixelSize.smaller
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    text: Translation.tr(root.step?.body ?? "")
                    wrapMode: Text.WordWrap
                    color: Appearance.m3colors.m3onSurfaceVariant
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    visible: (root.step?.keys.length ?? 0) > 0

                    Repeater {
                        model: root.step?.keys ?? []

                        delegate: RowLayout {
                            id: cap
                            required property int index
                            required property string modelData
                            spacing: 3

                            StyledText {
                                visible: cap.index > 0
                                text: "+"
                            }
                            KeyboardKey {
                                key: cap.modelData
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    RippleButton {
                        buttonText: Translation.tr("Skip")
                        onClicked: root.close()
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    RippleButton {
                        buttonText: Translation.tr("Back")
                        enabled: root.index > 0
                        onClicked: root.go(-1)
                    }
                    RippleButton {
                        // The focus owner for the whole surface, so the card
                        // above receives arrow and Escape events at all.
                        focus: tourWindow.visible
                        buttonText: root.index === root.steps.length - 1 ? Translation.tr("Done") : Translation.tr("Next")
                        onClicked: root.go(1)
                    }
                }
            }
        }
    }

    GlobalShortcut {
        name: "tourToggle"
        description: "Toggles the desktop tour on press"

        onPressed: root.toggle()
    }
}
