import qs.modules.common
import qs.modules.common.widgets
import qs.modules.common.functions
import qs.services
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

LazyLoader {
    id: root

    property Item hoverTarget
    default property Item contentItem
    property real popupBackgroundMargin: 0

    // Hover (default): popup follows the cursor over the bar item.
    // Click: clicking the bar item pins the popup open; clicking the item
    // again or anywhere outside closes it.
    property bool clickToShow: Config.options.bar.tooltips.clickToShow
    property bool pinned: false

    // Keyboard: `qs ipc call bar popup N` (Bar.qml) sets keyboardPopup on the
    // bar window of the focused monitor; the popup whose keyIndex matches opens.
    // A widget that is not on the bar right now has no place to hang from.
    property int keyIndex: 0
    readonly property var barWindow: root.QsWindow?.window ?? null
    readonly property bool keyboardOpen: root.keyIndex > 0 && (root.barWindow?.keyboardPopup ?? 0) === root.keyIndex
        && (root.hoverTarget?.visible ?? false)

    active: keyboardOpen || (clickToShow ? pinned : (hoverTarget && hoverTarget.containsMouse))

    function toggle() { root.pinned = !root.pinned; }
    function close() {
        root.pinned = false;
        if (root.keyboardOpen) root.barWindow.keyboardPopup = 0;
    }

    // Named property so it isn't captured by the `contentItem` default property.
    property Connections clickWatcher: Connections {
        target: root.hoverTarget
        enabled: root.clickToShow && root.hoverTarget !== null
        function onClicked(mouse) { root.toggle(); }
    }

    component: PanelWindow {
        id: popupWindow
        color: "transparent"

        anchors.left: !Config.options.bar.vertical || (Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.right: Config.options.bar.vertical && Config.options.bar.bottom
        anchors.top: Config.options.bar.vertical || (!Config.options.bar.vertical && !Config.options.bar.bottom)
        anchors.bottom: !Config.options.bar.vertical && Config.options.bar.bottom

        implicitWidth: popupBackground.implicitWidth + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin
        implicitHeight: popupBackground.implicitHeight + Appearance.sizes.elevationMargin * 2 + root.popupBackgroundMargin

        mask: Region {
            item: popupBackground
        }

        exclusionMode: ExclusionMode.Ignore
        exclusiveZone: 0

        /// A popup should clear the bar by exactly as much as a tiled window
        /// does, so the two read as one system: Hyprland's gaps_out plus its
        /// 1px border. The elevation margin is shadow allowance held inside
        /// this window, so it comes out of the offset instead of adding to it.
        readonly property real barEdgeGap: Appearance.sizes.hyprlandGapsOut + 1
        function barEdgeOffset(barExtent) {
            return barExtent - Appearance.sizes.elevationMargin + barEdgeGap;
        }
        margins {
            left: {
                if (!Config.options.bar.vertical) return root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    (root.hoverTarget.width - popupBackground.implicitWidth) / 2, 0
                ).x;
                return Appearance.sizes.verticalBarWidth
            }
            top: {
                if (!Config.options.bar.vertical) return popupWindow.barEdgeOffset(Appearance.sizes.barHeight);
                return root.QsWindow?.mapFromItem(
                    root.hoverTarget,
                    (root.hoverTarget.height - popupBackground.implicitHeight) / 2, 0
                ).y;
            }
            right: popupWindow.barEdgeOffset(Appearance.sizes.verticalBarWidth)
            bottom: popupWindow.barEdgeOffset(Appearance.sizes.barHeight)
        }
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        // Only a keyboard-opened popup takes the keyboard, and only OnDemand:
        // Exclusive breaks click-outside-to-close (docs/navigation.md).
        WlrLayershell.keyboardFocus: root.keyboardOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None

        // Click and keyboard modes: register with the shared focus grab so a
        // click anywhere outside the popup dismisses it. A hover popup that is
        // then keyboard-opened joins the grab late, through the Connections.
        readonly property bool dismissable: root.clickToShow || root.keyboardOpen
        Component.onCompleted: {
            if (popupWindow.dismissable) GlobalFocusGrab.addDismissable(popupWindow);
        }
        Component.onDestruction: {
            GlobalFocusGrab.removeDismissable(popupWindow);
        }
        onDismissableChanged: {
            if (popupWindow.dismissable) GlobalFocusGrab.addDismissable(popupWindow);
            else GlobalFocusGrab.removeDismissable(popupWindow);
        }
        Connections {
            target: GlobalFocusGrab
            enabled: popupWindow.dismissable
            function onDismissed() { root.close(); }
        }

        StyledRectangularShadow {
            target: popupBackground
        }

        Rectangle {
            id: popupBackground
            readonly property real margin: 10
            anchors {
                fill: parent
                leftMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.left)
                rightMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.right)
                topMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.top)
                bottomMargin: Appearance.sizes.elevationMargin + root.popupBackgroundMargin * (!popupWindow.anchors.bottom)
            }
            implicitWidth: root.contentItem.implicitWidth + margin * 2
            implicitHeight: root.contentItem.implicitHeight + margin * 2
            color: Appearance.m3colors.m3surfaceContainer
            radius: Appearance.rounding.small
            children: [root.contentItem]

            focus: root.keyboardOpen
            Keys.onEscapePressed: root.close()

            border.width: 1
            border.color: Appearance.colors.colLayer0Border
        }
    }
}
