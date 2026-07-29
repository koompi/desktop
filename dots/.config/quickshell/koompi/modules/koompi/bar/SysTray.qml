import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Services.SystemTray
import qs.services
import qs.modules.common
import qs.modules.common.widgets

Item {
    id: root
    implicitWidth: gridLayout.implicitWidth
    implicitHeight: gridLayout.implicitHeight
    property bool vertical: false
    property bool invertSide: false
    property bool showSeparator: true
    property var activeMenu: null

    property list<var> pinnedItems: TrayService.pinnedItems
    property list<var> unpinnedItems: TrayService.unpinnedItems

    function grabFocus() {
        focusGrab.active = true;
    }

    function setExtraWindowAndGrabFocus(window) {
        if (root.activeMenu && root.activeMenu !== window) {
            if (typeof root.activeMenu.close === "function")
                root.activeMenu.close();
            root.activeMenu = null;
        }
        root.activeMenu = window;
        root.grabFocus();
    }

    function releaseFocus() {
        focusGrab.active = false;
    }

    HyprlandFocusGrab {
        id: focusGrab
        active: false
        windows: [root.activeMenu]
        onCleared: {
            if (root.activeMenu) {
                root.activeMenu.close();
                root.activeMenu = null;
            }
        }
    }

    GridLayout {
        id: gridLayout
        columns: root.vertical ? 1 : -1
        anchors.fill: parent
        rowSpacing: 8
        columnSpacing: 15

        // Previously-hidden (unpinned) tray items, shown inline on the bar.
        // Replaces the broken expand_more overflow button.
        Repeater {
            model: ScriptModel {
                values: root.unpinnedItems
            }

            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                Layout.fillHeight: !root.vertical
                Layout.fillWidth: root.vertical
                onMenuClosed: root.releaseFocus();
                onMenuOpened: (qsWindow) => root.setExtraWindowAndGrabFocus(qsWindow);
            }
        }

        Repeater {
            model: ScriptModel {
                values: root.pinnedItems
            }

            delegate: SysTrayItem {
                required property SystemTrayItem modelData
                item: modelData
                Layout.fillHeight: !root.vertical
                Layout.fillWidth: root.vertical
                onMenuClosed: root.releaseFocus();
                onMenuOpened: (qsWindow) => {
                    root.setExtraWindowAndGrabFocus(qsWindow);
                }
            }
        }
    }
}
