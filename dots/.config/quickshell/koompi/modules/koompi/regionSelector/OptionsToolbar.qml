pragma ComponentBehavior: Bound
import qs
import qs.modules.common
import qs.modules.common.functions
import qs.modules.common.widgets
import qs.services
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Qt5Compat.GraphicalEffects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland

// Options toolbar
Toolbar {
    id: root

    // Use a synchronizer on these
    property var action
    property var selectionMode
    // Signals
    signal dismiss()
    signal fullScreenRequested()

    // Capture the whole screen without dragging a selection. The selector is the
    // only screenshot UI, so it has to offer the case where you want all of it.
    IconAndTextToolbarButton {
        iconText: "fullscreen"
        buttonText: Translation.tr("Full screen")
        onClicked: root.fullScreenRequested()
        StyledToolTip {
            text: Translation.tr("Capture this entire screen")
        }
    }

    // The tab writes the mode and the mode writes the tab, so neither side can
    // be a binding: a binding on currentIndex closes a loop on itself, Qt drops
    // it, and the tabs stay stuck on whatever mode the selector opened in.
    function syncTab() {
        tabBar.setCurrentIndex(root.selectionMode === RegionSelection.SelectionMode.Circle ? 1 : 0);
    }
    onSelectionModeChanged: root.syncTab()
    Component.onCompleted: root.syncTab()

    ToolbarTabBar {
        id: tabBar
        tabButtonList: [
            {"icon": "activity_zone", "name": Translation.tr("Rect")},
            {"icon": "gesture", "name": Translation.tr("Circle")}
        ]
        onCurrentIndexChanged: {
            root.selectionMode = currentIndex === 0 ? RegionSelection.SelectionMode.RectCorners : RegionSelection.SelectionMode.Circle;
        }
    }
}
